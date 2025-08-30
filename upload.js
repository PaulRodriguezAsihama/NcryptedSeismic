const AWS = require('aws-sdk');
const fs = require('fs');
const path = require('path');
const mime = require('mime-types');

// CONFIGURA TUS CLAVES Y NOMBRE DEL BUCKET
const filebase = new AWS.S3({
  endpoint: 'https://s3.filebase.com',
  accessKeyId: 'B04E5FA2C40043B5E2EE',
  secretAccessKey: 'BfeT8sJFGLZCB8k2I7pVlSd5s7zTSfopg37u1T1X',
  signatureVersion: 'v4',
});

const BUCKET = 'seismic';
const filePath = ''; // Ruta al archivo que deseas subir

async function upload() {
  const fileContent = fs.readFileSync(filePath);
  const fileName = path.basename(filePath);
  const contentType = mime.lookup(fileName) || 'application/octet-stream';

  const params = {
    Bucket: BUCKET,
    Key: fileName,
    Body: fileContent,
    ContentType: contentType,
  };

  try {
    await filebase.putObject(params).promise();
    const cid = `ipfs://${fileName}`;
    console.log('✅ Archivo subido con éxito');
    console.log('📦 CID IPFS:', cid);
    console.log('🌍 URL pública:', `https://${BUCKET}.s3.filebase.com/${fileName}`);
  } catch (err) {
    console.error('❌ Error al subir:', err.message);
  }
}

upload();
