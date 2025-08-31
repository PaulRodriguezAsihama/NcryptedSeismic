# NcryptoSeismic
#Seismic AI & Blockchain

This project aims to automate the detection of faults and other seismic attributes using Artificial Intelligence, starting with Neural Networks. The workflow integrates seismic data (such as SEG-Y files) and leverages blockchain technology to encrypt and control access to these sensitive datasets.
We used the Lisk scaffold version to deploy and test the initial contract, Zama for secure encryption of SGY files, and IA for initial fault detection.

## Main Features

- **Seismic Fault Detection with AI:** Use deep learning models to analyze seismic data and automatically detect faults and other geological features.
- **Blockchain Data Encryption:** Store references to encrypted seismic files (SEG-Y) on-chain, ensuring only the owner or authorized users can access the data.
- **Smart Contract Registry:** The `SeismicRegistry` contract allows registration of datasets, licensing, purchases, and secure access management for seismic data.
- **dApp Scaffold:** Built with NextJS, Hardhat, RainbowKit, Wagmi, Viem, and Typescript for rapid development and testing of decentralized applications.

## Project Structure

- `scaffold-lisk/packages/hardhat/contracts/SeismicRegistry2.sol`: Main smart contract for seismic data registration, licensing, and encrypted access control.
- `scaffold-lisk/packages/hardhat/test/SeismicRegistry.test.ts`: Unit tests for the registry contract, covering dataset registration, licensing, purchases, and withdrawals.
- `scaffold-lisk/packages/hardhat/deploy/00_deploy_seismic_registry.ts`: Deployment script for the registry contract.
- `scaffold-lisk/packages/nextjs/`: Frontend scaffold for interacting with smart contracts and visualizing seismic data and AI results.

## Quickstart

1. **Clone and Install Dependencies**

   ```bash
   git clone <your-repo-url>
   cd scaffold-lisk
   yarn install
   ```

2. **Start Local Blockchain**

   ```bash
   yarn chain
   ```

3. **Deploy Contracts**

   ```bash
   yarn deploy
   ```

4. **Run Frontend**

   ```bash
   yarn start
   ```

   Visit `http://localhost:3000` to interact with your dApp.

5. **Run Smart Contract Tests**
   ```bash
   yarn test packages/hardhat/test/SeismicRegistry.test.ts
   ```

## How It Works

- **AI Models:** Train and run neural networks to detect faults in seismic data. Results can be visualized and stored.
- **Data Encryption:** Seismic files are encrypted off-chain; only references (CIDs) and access policies are stored on-chain.
- **Access Control:** The smart contract ensures only the owner or licensed users can retrieve decryption keys for seismic data.
- **Licensing & Purchases:** Users can license datasets, pay with ETH or ERC20 tokens, and withdraw earnings securely.

## Deployment to Testnets

See the main README for instructions on deploying to Superchain testnets (Optimism, Arbitrum, etc.).

## Documentation

- Smart contract: `SeismicRegistry2.sol`
- Tests: `SeismicRegistry.test.ts`
- Deployment: `00_deploy_seismic_registry.ts`
- Frontend: `packages/nextjs/`

For more details, refer to the Scaffold-ETH 2 [documentation](https://docs.scaffoldeth.io).

2. Run a local network in the first terminal:

```
yarn chain
```

This command starts a local Ethereum network using Hardhat. The network runs on your local machine and can be used for testing and development. You can customize the network configuration in `hardhat.config.ts`.

3. On a second terminal, deploy the test contract:

```
yarn deploy
```

This command deploys a test smart contract to the local network. The contract is located in `packages/hardhat/contracts` and can be modified to suit your needs. The `yarn deploy` command uses the deploy script located in `packages/hardhat/deploy` to deploy the contract to the network. You can also customize the deploy script.

4. On the same terminal, start your NextJS app:

```
yarn start
```

Visit your app on: `http://localhost:3000`. You can interact with your smart contract using the `Debug Contracts` page. You can tweak the app config in `packages/nextjs/scaffold.config.ts`.

Run smart contract test with `yarn hardhat:test`

- Edit your smart contract `YourContract.sol` in `packages/hardhat/contracts`
- Edit your frontend in `packages/nextjs/pages`
- Edit your deployment scripts in `packages/hardhat/deploy`

## Deploy Contracts to Superchain Testnet(s)

To deploy contracts to a remote testnet (e.g. Optimism Sepolia), follow the steps below:

1. Get Superchain Sepolia ETH from the [Superchain Faucet](https://app.optimism.io/faucet)

2. Inside the `packages/hardhat` directory, copy `.env.example` to `.env`.

   ```bash
   cd packages/hardhat && cp .env.example .env
   ```

3. Edit your `.env` to specify the environment variables. Only specifying the `DEPLOYER_PRIVATE_KEY` is necessary here. The contract will be deployed from the address associated with this private key, so make sure it has enough Sepolia ETH.

   ```bash
   DEPLOYER_PRIVATE_KEY = "your_private_key_with_sepolia_ETH";
   ```

4. Inside `scaffold-lisk`, run

   ```bash
   yarn deploy --network-options
   ```

   Use spacebar to make your selection(s). This command deploys all smart contracts in `packages/hardhat/contracts` to the selected network(s). Alternatively, you can try

   ```bash
   yarn deploy --network networkName
   ```

   Network names are found in `hardhat.config.js`. Please ensure you have enough Sepolia ETH on all these Superchains. If the deployments are successful, you will see the deployment tx hash on the terminal.

## Adding Foundry

Hardhat's NodeJS stack and cleaner deployment management makes it a better default for Scaffold-Lisk.

To add Foundry to Scaffold-Lisk, follow this simple [tutorial](https://hardhat.org/hardhat-runner/docs/advanced/hardhat-and-foundry) by Hardhat. We recommend users who want more robust and faster testing to add Foundry.

## Documentation

We highly recommend visiting the original [docs](https://docs.scaffoldeth.io) to learn how to start building with Scaffold-ETH 2.

To know more about its features, check out their [website](https://scaffoldeth.io).
