// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
  SeismicRegistry v2 -- mejoras:
  - require(msg.value >= price) en recordPurchase
  - soporte de pagos ERC20 (recordPurchaseERC20 + withdrawERC20)
  - event Withdrawn / WithdrawnERC20
  - storeEncryptedKeyCID(assetId, licenseId, cid) para guardar referencia a key/Policy CID
  - revokeLicense, transferAsset
  - ReentrancyGuard para evitar reentrancy en retiros
  - Ownable(initialOwner) (OpenZeppelin v5 constructor)
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SeismicRegistry is Ownable, ReentrancyGuard {
    enum Kind { Dataset, Model }

    struct Asset {
        uint256 id;
        Kind kind;
        address owner;
        bytes32 contentHash;
        string uri;
        string licenseTerms;
        string cid; // CID of encrypted payload manifest
        bool active;
    }

    struct License {
        uint256 id;
        uint256 assetId;
        address licensor;   // owner at issuance time
        address licensee;   // intended recipient (can be address(0) if open)
        string termsRef;    // ipfs://... or text
        uint256 price;      // price in wei (for ETH purchases)
        bool revoked;
        uint64 issuedAt;
    }

    struct Purchase {
        uint256 id;
        uint256 licenseId;
        address buyer;
        uint256 amount; // in wei for ETH purchases; for ERC20 purchases amount recorded separately
        uint64 paidAt;
    }

    uint256 private _assetSeq;
    uint256 private _licenseSeq;
    uint256 private _purchaseSeq;

    mapping(uint256 => Asset) public assets;
    mapping(bytes32 => uint256) public assetByHash;
    mapping(uint256 => License) public licenses;
    mapping(uint256 => uint256[]) public licensesOf;
    mapping(uint256 => Purchase) public purchases;
    mapping(uint256 => uint256[]) public purchasesOf;

    // pending withdrawals in ETH
    mapping(address => uint256) public pendingWithdrawals;

    // pending withdrawals for ERC20: token => address => amount
    mapping(address => mapping(address => uint256)) public pendingERC20Withdrawals;

    // store pointer to encrypted key / PRE policy (cid) per (asset, license)
    mapping(uint256 => mapping(uint256 => string)) public encryptedKeyCID; // assetId => licenseId => cid

    // Events
    event DatasetRegistered(uint256 indexed assetId, address indexed owner, bytes32 contentHash, string uri, string licenseTerms);
    event ModelRegistered(uint256 indexed assetId, address indexed owner, bytes32 contentHash, string uri, string licenseTerms);
    event CIDStored(uint256 indexed assetId, string cid);
    event LicenseIssued(uint256 indexed licenseId, uint256 indexed assetId, address indexed licensee, uint256 price, string termsRef);
    event LicenseRevoked(uint256 indexed licenseId);
    event PurchaseRecorded(uint256 indexed purchaseId, uint256 indexed licenseId, address indexed buyer, uint256 amount);
    event PurchaseRecordedERC20(uint256 indexed purchaseId, uint256 indexed licenseId, address indexed buyer, address token, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);
    event WithdrawnERC20(address indexed who, address indexed token, uint256 amount);
    event KeyCIDStored(uint256 indexed assetId, uint256 indexed licenseId, string cid);
    event AssetTransferred(uint256 indexed assetId, address indexed from, address indexed to);

    // Modifiers
    modifier onlyAssetOwner(uint256 assetId) {
        require(assets[assetId].owner == msg.sender, "Not asset owner");
        _;
    }

    modifier assetExists(uint256 assetId) {
        require(assets[assetId].owner != address(0), "Asset not found");
        _;
    }

    modifier licenseExists(uint256 licenseId) {
        require(licenses[licenseId].licensor != address(0), "License not found");
        _;
    }

    // Constructor requires initial owner (OpenZeppelin v5 Ownable pattern)
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ==== Registration functions ====

    function registerDataset(bytes32 contentHash, string calldata uri, string calldata licenseTerms) external returns (uint256) {
        require(contentHash != bytes32(0), "hash required");
        require(assetByHash[contentHash] == 0, "already registered");
        _assetSeq++;
        uint256 id = _assetSeq;
        assets[id] = Asset(id, Kind.Dataset, msg.sender, contentHash, uri, licenseTerms, "", true);
        assetByHash[contentHash] = id;
        emit DatasetRegistered(id, msg.sender, contentHash, uri, licenseTerms);
        return id;
    }

    function registerModel(bytes32 contentHash, string calldata uri, string calldata licenseTerms) external returns (uint256) {
        require(contentHash != bytes32(0), "hash required");
        require(assetByHash[contentHash] == 0, "already registered");
        _assetSeq++;
        uint256 id = _assetSeq;
        assets[id] = Asset(id, Kind.Model, msg.sender, contentHash, uri, licenseTerms, "", true);
        assetByHash[contentHash] = id;
        emit ModelRegistered(id, msg.sender, contentHash, uri, licenseTerms);
        return id;
    }

    function storeCID(uint256 assetId, string calldata cid) external assetExists(assetId) onlyAssetOwner(assetId) {
        assets[assetId].cid = cid;
        emit CIDStored(assetId, cid);
    }

    // store reference to encrypted key or PRE policy (IPFS cid) for a given license
    function storeEncryptedKeyCID(uint256 assetId, uint256 licenseId, string calldata cid) external assetExists(assetId) onlyAssetOwner(assetId) {
        // license must relate to the asset
        require(licenseId > 0 && licenseId <= _licenseSeq, "invalid licenseId");
        require(licenses[licenseId].assetId == assetId, "license mismatch");
        encryptedKeyCID[assetId][licenseId] = cid;
        emit KeyCIDStored(assetId, licenseId, cid);
    }

    // ==== Licensing ====

    function issueLicense(uint256 assetId, address licensee, string calldata termsRef, uint256 price)
        external assetExists(assetId) onlyAssetOwner(assetId) returns (uint256)
    {
        _licenseSeq++;
        uint256 id = _licenseSeq;
        licenses[id] = License(id, assetId, msg.sender, licensee, termsRef, price, false, uint64(block.timestamp));
        licensesOf[assetId].push(id);
        emit LicenseIssued(id, assetId, licensee, price, termsRef);
        return id;
    }

    function revokeLicense(uint256 licenseId) external licenseExists(licenseId) {
        License storage lic = licenses[licenseId];
        require(msg.sender == lic.licensor || msg.sender == owner(), "not licensor or contract owner");
        lic.revoked = true;
        emit LicenseRevoked(licenseId);
    }

    // transfer registral ownership of asset
    function transferAsset(uint256 assetId, address to) external assetExists(assetId) onlyAssetOwner(assetId) {
        require(to != address(0), "zero address");
        address from = assets[assetId].owner;
        assets[assetId].owner = to;
        emit AssetTransferred(assetId, from, to);
    }

    // ==== Purchases (ETH) ====
    // Enforce price; collects funds to pendingWithdrawals[licensor]
    function recordPurchase(uint256 licenseId) external payable licenseExists(licenseId) returns (uint256) {
        License memory lic = licenses[licenseId];
        require(!lic.revoked, "license revoked");
        require(msg.value > 0, "no payment");
        require(lic.price > 0, "license price not set");
        require(msg.value >= lic.price, "insufficient payment");

        _purchaseSeq++;
        uint256 id = _purchaseSeq;

        purchases[id] = Purchase(id, licenseId, msg.sender, msg.value, uint64(block.timestamp));
        purchasesOf[licenseId].push(id);

        pendingWithdrawals[lic.licensor] += msg.value;

        emit PurchaseRecorded(id, licenseId, msg.sender, msg.value);
        return id;
    }

    // ==== Purchases (ERC20) ====
    // Buyer must approve the contract to spend `amount` of token before calling
    function recordPurchaseERC20(address token, uint256 licenseId, uint256 amount) external licenseExists(licenseId) returns (uint256) {
        require(token != address(0), "token zero");
        License memory lic = licenses[licenseId];
        require(!lic.revoked, "license revoked");
        require(amount > 0, "zero amount");
        require(lic.price > 0, "license price not set");

        // Note: price is in wei (ETH). For ERC20 we assume buyer and seller agreed amount in token units.
        // It's the off-chain business responsibility to match license.price semantics vs token amount.
        // The contract only enforces token transfer success.
        IERC20 erc = IERC20(token);
        bool ok = erc.transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom failed");

        _purchaseSeq++;
        uint256 id = _purchaseSeq;
        purchases[id] = Purchase(id, licenseId, msg.sender, amount, uint64(block.timestamp));
        purchasesOf[licenseId].push(id);

        // credit licensor in token pool
        pendingERC20Withdrawals[token][lic.licensor] += amount;

        emit PurchaseRecordedERC20(id, licenseId, msg.sender, token, amount);
        return id;
    }

    // ==== Withdrawals ====
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    // withdraw ERC20 tokens
    function withdrawERC20(address token) external nonReentrant {
        uint256 amount = pendingERC20Withdrawals[token][msg.sender];
        require(amount > 0, "nothing to withdraw");
        pendingERC20Withdrawals[token][msg.sender] = 0;
        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "token transfer failed");
        emit WithdrawnERC20(msg.sender, token, amount);
    }

    // ==== View helpers ====
    function getLicensesOfAsset(uint256 assetId) external view returns (uint256[] memory) {
        return licensesOf[assetId];
    }

    function getPurchasesOfLicense(uint256 licenseId) external view returns (uint256[] memory) {
        return purchasesOf[licenseId];
    }

    function getEncryptedKeyCID(uint256 assetId, uint256 licenseId) external view returns (string memory) {
        return encryptedKeyCID[assetId][licenseId];
    }
}
