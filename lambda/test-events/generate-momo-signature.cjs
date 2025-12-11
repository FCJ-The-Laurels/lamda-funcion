const crypto = require('crypto');

// MoMo test credentials
const accessKey = 'F8BBA842ECF85';
const secretKey = 'K951B6PE1waDMi640xX08PD3vg6EkVlz';

// Test IPN data
const ipnData = {
  partnerCode: 'MOMO',
  orderId: 'MOMO1765042430139',
  requestId: 'MOMO1765042430139',
  amount: '50000',
  orderInfo: 'Goi PREMIUM - LeafLungs',
  orderType: 'momo_wallet',
  transId: '4000000001', // Test transaction ID
  resultCode: '0',
  message: 'Successful.',
  payType: 'qr',
  responseTime: '1733445600000',
  extraData: Buffer.from(JSON.stringify({
    userId: 'test-user-123',
    packageType: 'PREMIUM'
  })).toString('base64')
};

// Generate signature for IPN
const rawSignature =
  'accessKey=' + accessKey +
  '&amount=' + ipnData.amount +
  '&extraData=' + ipnData.extraData +
  '&message=' + ipnData.message +
  '&orderId=' + ipnData.orderId +
  '&orderInfo=' + ipnData.orderInfo +
  '&orderType=' + ipnData.orderType +
  '&partnerCode=' + ipnData.partnerCode +
  '&payType=' + ipnData.payType +
  '&requestId=' + ipnData.requestId +
  '&responseTime=' + ipnData.responseTime +
  '&resultCode=' + ipnData.resultCode +
  '&transId=' + ipnData.transId;

const signature = crypto
  .createHmac('sha256', secretKey)
  .update(rawSignature)
  .digest('hex');

ipnData.signature = signature;

console.log('IPN Test Event:');
console.log(JSON.stringify({
  body: JSON.stringify(ipnData),
  headers: {
    'Content-Type': 'application/json'
  },
  httpMethod: 'POST'
}, null, 2));

console.log('\nIPN Payload for curl:');
console.log(JSON.stringify(ipnData, null, 2));
