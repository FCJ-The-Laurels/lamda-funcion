import crypto from 'crypto';

// Simple fetch wrapper with timeout
async function fetchWithTimeout(url, options = {}, timeoutMs = 10000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...options, signal: controller.signal });
    return res;
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Calculate subscription expiry date
 * @param {number} days - Number of days to add
 * @returns {string} ISO8601 timestamp
 */
function calculateExpiryDate(days) {
  const now = new Date();
  const expiryDate = new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
  return expiryDate.toISOString();
}

export const handler = async (event) => {
  console.log('📥 IPN Callback Received:', JSON.stringify(event, null, 2));

  try {
    // Extract environment variables
    const {
      MOMO_ACCESS_KEY,
      MOMO_SECRET_KEY,
      BACKEND_API_URL,
      BACKEND_API_KEY
    } = process.env;

    // Validate environment variables
    if (!MOMO_ACCESS_KEY || !MOMO_SECRET_KEY || !BACKEND_API_URL || !BACKEND_API_KEY) {
      console.error('❌ Missing required environment variables');
      // Still return 204 to prevent MoMo retries
      return { statusCode: 204, body: '' };
    }

    // Parse IPN payload
    const ipnData = JSON.parse(event.body || '{}');

    const {
      partnerCode,
      orderId,
      requestId,
      amount,
      orderInfo,
      orderType,
      transId,
      resultCode,
      message,
      payType,
      responseTime,
      extraData,
      signature
    } = ipnData;

    console.log(`📦 IPN Data - Order: ${orderId}, TransId: ${transId}, ResultCode: ${resultCode}`);

    // STEP 1: Validate signature (CRITICAL for security)
    const rawSignature =
      'accessKey=' + MOMO_ACCESS_KEY +
      '&amount=' + amount +
      '&extraData=' + extraData +
      '&message=' + message +
      '&orderId=' + orderId +
      '&orderInfo=' + orderInfo +
      '&orderType=' + orderType +
      '&partnerCode=' + partnerCode +
      '&payType=' + payType +
      '&requestId=' + requestId +
      '&responseTime=' + responseTime +
      '&resultCode=' + resultCode +
      '&transId=' + transId;

    const expectedSignature = crypto
      .createHmac('sha256', MOMO_SECRET_KEY)
      .update(rawSignature)
      .digest('hex');

    console.log(`🔐 Expected signature: ${expectedSignature}`);
    console.log(`🔐 Received signature: ${signature}`);

    if (signature !== expectedSignature) {
      console.error('❌ SECURITY ALERT: Invalid signature - possible security breach!');
      console.error(`Raw signature string: ${rawSignature}`);
      // CRITICAL: Still return 204 to prevent MoMo from retrying invalid requests
      return { statusCode: 204, body: '' };
    }

    console.log('✅ Signature validation passed');

    // STEP 2: (Skipped) No check-transaction endpoint available, proceed directly

    // STEP 3: Parse extraData to get userId, packageType, and programId
    let userId, packageType, programId;

    try {
      const extraDataDecoded = JSON.parse(
        Buffer.from(extraData, 'base64').toString('utf8')
      );

      userId = extraDataDecoded.userId;
      packageType = extraDataDecoded.packageType;
      programId = extraDataDecoded.programId; // Optional - only for trial upgrade

      console.log(`👤 User ID: ${userId}`);
      console.log(`📦 Package Type: ${packageType}`);
      console.log(`🎯 Program ID: ${programId || 'N/A (direct subscription)'}`);

      if (!userId || !packageType) {
        throw new Error('Missing userId or packageType in extraData');
      }
    } catch (error) {
      console.error('❌ Error parsing extraData:', error.message);
      console.error(`ExtraData received: ${extraData}`);
      // Cannot process without user info - return 204 to prevent retries
      return { statusCode: 204, body: '' };
    }

    // STEP 4: Process payment result
    if (resultCode === 0) {
      // Payment successful - update both Program Service (if trial) and User Service
      console.log(`✅ Payment successful - updating user ${userId} to ${packageType}`);

      // STEP 4A: Upgrade Program from trial (if programId exists)
        if (programId) {
          console.log(`🔄 Upgrading program ${programId} from trial...`);
          try {
            const res = await fetchWithTimeout(
              `${BACKEND_API_URL}/api/programs/${programId}/upgrade-from-trial`,
              {
                method: 'POST',
                headers: {
                  'X-User-Id': userId,
                  'X-User-Group': 'CUSTOMER',  // Required by Program Service HeaderUserContextFilter
                  'X-API-Key': BACKEND_API_KEY,
                  'Content-Type': 'application/json'
                },
                body: JSON.stringify({}),
              },
              10000
            );
            if (!res.ok) {
              const text = await res.text();
              throw new Error(`Program upgrade failed: ${res.status} ${text}`);
            }
            console.log(`✅ Program ${programId} upgraded from trial successfully`);
          } catch (error) {
            console.error('❌ Error upgrading program from trial:', error.message);
            // Continue to update User Service even if Program Service fails
            console.warn('⚠️ Continuing to update User Service despite Program Service error');
          }
        }

      // STEP 4B: Update User Service (by userId) with subscription/payment fields
      try {
        const subscriptionData = {
          // Subscription fields
          subscriptionTier: packageType,                    // "BASIC"|"PREMIUM"|"VIP"
          subscriptionStatus: 'ACTIVE',
          subscriptionExpiresAt: calculateExpiryDate(30),   // 30 days subscription

          // Payment fields
          paymentMethod: 'MOMO',
          lastPaymentId: String(transId),
          lastPaymentDate: new Date().toISOString(),
          lastPaymentAmount: amount,

          // Billing fields
          nextBillingDate: calculateExpiryDate(30),
          autoRenewal: false
        };

        console.log('📤 Updating User Service with subscription data:', JSON.stringify(subscriptionData, null, 2));

        const updateResponse = await fetchWithTimeout(
          `${BACKEND_API_URL}/api/user-info`,
          {
            method: 'PATCH',
            headers: {
              'X-User-Id': userId,
              'X-API-Key': BACKEND_API_KEY,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify(subscriptionData),
          },
          10000
        );

        if (!updateResponse.ok) {
          const text = await updateResponse.text();
          throw new Error(`User Service update failed: ${updateResponse.status} ${text}`);
        }

        const updateData = await updateResponse.text();
        console.log('✅ User subscription updated successfully:', updateData);
        console.log(`🎉 User ${userId} is now ${packageType} member!`);
        console.log(`💳 Payment ID: ${transId}, Amount: ${amount} VND`);
        console.log(`📅 Subscription expires: ${subscriptionData.subscriptionExpiresAt}`);
      } catch (error) {
        if (error.response?.status === 409) {
          // Duplicate transaction - already processed
          console.log(`⚠️ Transaction ${transId} already exists (409 Conflict) - idempotency`);
        } else {
          console.error('❌ Error updating subscription:', error.message);
          if (error.response) {
            console.error('User Service Error:', error.response.status, error.response.data);
          }
          // Log error but still return 204 to prevent infinite retries
          // Manual intervention may be needed for failed updates
          console.error(`⚠️ MANUAL CHECK REQUIRED: TransId ${transId}, User ${userId}, Package ${packageType}, Amount ${amount}`);
        }
      }
    } else {
      // Payment failed
      console.log(`❌ Payment failed - ResultCode: ${resultCode}, Message: ${message}`);
      console.log(`Order ${orderId} for user ${userId} was not successful`);
    }

    // STEP 5: ALWAYS return HTTP 204 No Content
    // This tells MoMo we received and processed the IPN successfully
    console.log('✅ IPN processing complete - returning 204');
    return {
      statusCode: 204,
      body: ''
    };

  } catch (error) {
    console.error('❌ Unexpected error in IPN handler:', error);
    console.error('Error stack:', error.stack);

    // CRITICAL: Always return 204 even on errors
    // This prevents MoMo from retrying and potentially causing duplicate processing
    return {
      statusCode: 204,
      body: ''
    };
  }
};
