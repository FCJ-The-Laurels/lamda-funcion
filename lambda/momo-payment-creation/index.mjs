import crypto from 'crypto';
import axios from 'axios';

export const handler = async (event) => {
  console.log('📥 Payment Creation Request:', JSON.stringify(event, null, 2));

  try {
    // Extract environment variables
    const {
      MOMO_PARTNER_CODE,
      MOMO_ACCESS_KEY,
      MOMO_SECRET_KEY,
      MOMO_ENDPOINT,
      BACKEND_API_URL,
      BACKEND_API_KEY,
      FRONTEND_REDIRECT_URL,
      IPN_URL
    } = process.env;

    // Validate environment variables
    if (!MOMO_PARTNER_CODE || !MOMO_ACCESS_KEY || !MOMO_SECRET_KEY || !MOMO_ENDPOINT) {
      throw new Error('Missing MoMo credentials in environment variables');
    }

    // Extract userId from Cognito authorizer context
    const userId = event.requestContext?.authorizer?.claims?.sub;
    const userGroups = event.requestContext?.authorizer?.claims?.['cognito:groups'];

    if (!userId) {
      console.error('❌ No userId found in authorizer context');
      return {
        statusCode: 401,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          resultCode: 401,
          message: 'Unauthorized - User ID not found'
        })
      };
    }

    console.log(`👤 User ID: ${userId}`);
    console.log(`👥 User Groups: ${userGroups}`);

    // Parse request body
    const body = JSON.parse(event.body || '{}');
    const { packageType, amount } = body;

    if (!packageType || !['BASIC', 'VIP', 'PREMIUM'].includes(packageType)) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          resultCode: 400,
          message: 'Invalid packageType. Must be BASIC, VIP, or PREMIUM'
        })
      };
    }

    // Set default amounts based on package type if not provided
    const packageAmounts = {
      BASIC: 0,
      VIP: 30000,
      PREMIUM: 50000
    };

    const paymentAmount = amount || packageAmounts[packageType];

    console.log(`💳 Package: ${packageType}, Amount: ${paymentAmount} VND`);

    // Check current membership status (optional validation)
    try {
      const membershipCheck = await axios.get(
        `${BACKEND_API_URL}/api/user-info/by-user-id`,
        {
          headers: {
            'X-User-Id': userId,
            'X-API-Key': BACKEND_API_KEY
          },
          timeout: 5000
        }
      );

      const currentMembership = membershipCheck.data?.membership || 'BASIC';
      console.log(`📊 Current membership: ${currentMembership}`);

      // Optional: Prevent downgrade or same package purchase
      if (currentMembership === packageType) {
        return {
          statusCode: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          },
          body: JSON.stringify({
            resultCode: 400,
            message: `You already have ${packageType} membership`
          })
        };
      }
    } catch (error) {
      console.warn('⚠️ Could not check current membership:', error.message);
      // Continue anyway - not critical for payment creation
    }

    // Generate unique IDs
    const timestamp = Date.now();
    const orderId = `MOMO${timestamp}`;
    const requestId = `MOMO${timestamp}`;

    // Prepare extraData with userId and packageType
    const extraDataObj = {
      userId: userId,
      packageType: packageType
    };
    const extraData = Buffer.from(JSON.stringify(extraDataObj)).toString('base64');

    console.log(`🔐 ExtraData: ${JSON.stringify(extraDataObj)}`);

    // Create MoMo payment request
    const momoRequest = {
      partnerCode: MOMO_PARTNER_CODE,
      accessKey: MOMO_ACCESS_KEY,
      requestId: requestId,
      amount: String(paymentAmount),
      orderId: orderId,
      orderInfo: `Goi ${packageType} - LeafLungs`,
      redirectUrl: FRONTEND_REDIRECT_URL,
      ipnUrl: IPN_URL,
      requestType: 'captureWallet',
      extraData: extraData,
      lang: 'vi'
    };

    // Generate signature
    const rawSignature =
      'accessKey=' + momoRequest.accessKey +
      '&amount=' + momoRequest.amount +
      '&extraData=' + momoRequest.extraData +
      '&ipnUrl=' + momoRequest.ipnUrl +
      '&orderId=' + momoRequest.orderId +
      '&orderInfo=' + momoRequest.orderInfo +
      '&partnerCode=' + momoRequest.partnerCode +
      '&redirectUrl=' + momoRequest.redirectUrl +
      '&requestId=' + momoRequest.requestId +
      '&requestType=' + momoRequest.requestType;

    console.log(`📝 Raw signature string: ${rawSignature}`);

    const signature = crypto
      .createHmac('sha256', MOMO_SECRET_KEY)
      .update(rawSignature)
      .digest('hex');

    momoRequest.signature = signature;

    console.log(`✅ Signature generated: ${signature}`);
    console.log(`📤 Calling MoMo API: ${MOMO_ENDPOINT}`);

    // Call MoMo API with 30 second timeout
    const momoResponse = await axios.post(
      MOMO_ENDPOINT,
      momoRequest,
      {
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 30000
      }
    );

    console.log('✅ MoMo Response:', JSON.stringify(momoResponse.data, null, 2));

    // Return response to frontend
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        resultCode: momoResponse.data.resultCode,
        payUrl: momoResponse.data.payUrl,
        orderId: momoResponse.data.orderId,
        requestId: momoResponse.data.requestId,
        message: momoResponse.data.message || 'Success'
      })
    };

  } catch (error) {
    console.error('❌ Payment Creation Error:', error);

    // Handle axios errors
    if (error.response) {
      console.error('MoMo API Error Response:', error.response.data);
      return {
        statusCode: error.response.status,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          resultCode: error.response.data.resultCode || 500,
          message: error.response.data.message || 'MoMo API Error',
          details: error.response.data
        })
      };
    }

    // Handle timeout errors
    if (error.code === 'ECONNABORTED') {
      return {
        statusCode: 504,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          resultCode: 504,
          message: 'Request timeout - MoMo API did not respond in time'
        })
      };
    }

    // Generic error
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        resultCode: 500,
        message: 'Internal server error',
        error: error.message
      })
    };
  }
};
