/**
 * Lambda Function: List Available Coaches (Public/Customer Access)
 *
 * Lambda này cho phép customer xem danh sách coaches available:
 * - List coaches với < 3 users (available coaches)
 * - Chỉ trả về thông tin công khai (name, email, specialization)
 * - Không cần admin role
 *
 * Được gọi qua API Gateway với Cognito Authorizer (cho customer)
 */

const {
  CognitoIdentityProviderClient,
  ListUsersInGroupCommand,
} = require('@aws-sdk/client-cognito-identity-provider');

const COGNITO_REGION = process.env.COGNITO_REGION || process.env.USER_POOL_REGION || 'us-east-1';
const USER_POOL_ID = process.env.USER_POOL_ID;

const cognitoClient = new CognitoIdentityProviderClient({ region: COGNITO_REGION });

/**
 * Helper: Create HTTP response
 */
const createResponse = (statusCode, body) => {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
    body: JSON.stringify(body),
  };
};

/**
 * Helper: Get user count for a coach (simplified - assume max 3)
 * In production, this should query from database to get actual assigned user count
 */
const getCoachUserCount = async (coachUsername) => {
  // TODO: Query from database to get actual assigned user count
  // For now, return a mock count (0-2) to show availability
  // This should be replaced with actual database query
  return Math.floor(Math.random() * 3); // Mock: 0-2 users
};

/**
 * Action: List available coaches (coaches with < 3 users)
 */
const listAvailableCoaches = async () => {
  try {
    const command = new ListUsersInGroupCommand({
      UserPoolId: USER_POOL_ID,
      GroupName: 'coach',
      Limit: 60, // Max coaches
    });

    const response = await cognitoClient.send(command);

    // Process coaches and filter available ones
    const coaches = await Promise.all(
      response.Users.map(async (user) => {
        const attributes = {};
        user.Attributes.forEach(attr => {
          attributes[attr.Name] = attr.Value;
        });

        // Get user count for this coach
        const userCount = await getCoachUserCount(user.Username);
        const isAvailable = userCount < 3;

        return {
          id: user.Username,
          username: user.Username,
          email: attributes.email,
          name: attributes.name || attributes.email?.split('@')[0] || 'Coach',
          specialization: attributes['custom:specialization'] || 'Cai thuốc lá',
          emailVerified: attributes.email_verified === 'true',
          status: user.UserStatus,
          enabled: user.Enabled,
          // Availability info
          assignedUsersCount: userCount,
          maxUsers: 3,
          isAvailable,
          // Only include if available
        };
      })
    );

    // Filter to only available coaches
    const availableCoaches = coaches.filter(coach => coach.isAvailable && coach.enabled);

    return createResponse(200, {
      success: true,
      coaches: availableCoaches,
      count: availableCoaches.length,
      totalCoaches: coaches.length,
    });
  } catch (error) {
    console.error('Error listing available coaches:', error);
    return createResponse(500, {
      success: false,
      error: 'Failed to list available coaches',
      message: error.message,
    });
  }
};

/**
 * Main Lambda Handler
 */
exports.handler = async (event) => {
  console.log('List Available Coaches Lambda:', JSON.stringify(event, null, 2));

  // Handle OPTIONS for CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return createResponse(200, { message: 'OK' });
  }

  try {
    // Only allow GET method
    if (event.httpMethod !== 'GET') {
      return createResponse(405, {
        success: false,
        error: 'Method not allowed',
        allowedMethods: ['GET'],
      });
    }

    // List available coaches
    return await listAvailableCoaches();
  } catch (error) {
    console.error('Unhandled error:', error);
    return createResponse(500, {
      success: false,
      error: 'Internal server error',
      message: error.message,
    });
  }
};

