/**
 * Lambda Function: Admin Manage Coaches
 *
 * Lambda này cho phép admin:
 * 1. Assign user vào coach group
 * 2. Remove user khỏi coach group
 * 3. List all coaches
 * 4. List all users (để admin chọn)
 *
 * Được gọi qua API Gateway với Cognito Authorizer
 * Chỉ admin mới có quyền gọi API này
 */

const {
  CognitoIdentityProviderClient,
  AdminAddUserToGroupCommand,
  AdminRemoveUserFromGroupCommand,
  AdminListGroupsForUserCommand,
  ListUsersInGroupCommand,
  ListUsersCommand,
  AdminCreateUserCommand,
  AdminGetUserCommand,
} = require('@aws-sdk/client-cognito-identity-provider');

// Use COGNITO_REGION instead of AWS_REGION (which is reserved)
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
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
    body: JSON.stringify(body),
  };
};

/**
 * Helper: Verify user is admin
 */
const verifyAdminAccess = (event) => {
  const claims = event.requestContext?.authorizer?.claims;

  if (!claims) {
    return { authorized: false, error: 'No authorization claims found' };
  }

  // Check if user belongs to admin group
  const groups = claims['cognito:groups'];
  const groupsArray = groups ? (Array.isArray(groups) ? groups : groups.split(',')) : [];

  if (!groupsArray.includes('admin')) {
    return { authorized: false, error: 'Access denied. Admin role required.' };
  }

  return { authorized: true, email: claims.email };
};

/**
 * Action: List all coaches
 */
const listCoaches = async () => {
  try {
    const command = new ListUsersInGroupCommand({
      UserPoolId: USER_POOL_ID,
      GroupName: 'coach',
      Limit: 60, // Max coaches
    });

    const response = await cognitoClient.send(command);

    const coaches = response.Users.map(user => {
      const attributes = {};
      user.Attributes.forEach(attr => {
        attributes[attr.Name] = attr.Value;
      });

      return {
        username: user.Username,
        email: attributes.email,
        name: attributes.name || attributes.email,
        emailVerified: attributes.email_verified === 'true',
        status: user.UserStatus,
        enabled: user.Enabled,
        createdAt: user.UserCreateDate,
      };
    });

    return createResponse(200, {
      success: true,
      coaches,
      count: coaches.length,
    });
  } catch (error) {
    console.error('Error listing coaches:', error);
    return createResponse(500, {
      success: false,
      error: 'Failed to list coaches',
      message: error.message,
    });
  }
};

/**
 * Action: List all users (for admin to select and assign as coach)
 */
const listUsers = async (event) => {
  try {
    // Parse query parameters
    const limit = event.queryStringParameters?.limit || 20;
    const paginationToken = event.queryStringParameters?.paginationToken;

    const command = new ListUsersCommand({
      UserPoolId: USER_POOL_ID,
      Limit: parseInt(limit),
      PaginationToken: paginationToken,
    });

    const response = await cognitoClient.send(command);

    const users = await Promise.all(
      response.Users.map(async (user) => {
        const attributes = {};
        user.Attributes.forEach(attr => {
          attributes[attr.Name] = attr.Value;
        });

        // Get user's groups
        try {
          const groupsCommand = new AdminListGroupsForUserCommand({
            UserPoolId: USER_POOL_ID,
            Username: user.Username,
          });
          const groupsResponse = await cognitoClient.send(groupsCommand);
          const groups = groupsResponse.Groups.map(g => g.GroupName);

          return {
            username: user.Username,
            email: attributes.email,
            name: attributes.name || attributes.email,
            emailVerified: attributes.email_verified === 'true',
            status: user.UserStatus,
            enabled: user.Enabled,
            groups,
            createdAt: user.UserCreateDate,
          };
        } catch (error) {
          console.error(`Error getting groups for user ${user.Username}:`, error);
          return {
            username: user.Username,
            email: attributes.email,
            name: attributes.name || attributes.email,
            groups: [],
          };
        }
      })
    );

    return createResponse(200, {
      success: true,
      users,
      count: users.length,
      paginationToken: response.PaginationToken,
    });
  } catch (error) {
    console.error('Error listing users:', error);
    return createResponse(500, {
      success: false,
      error: 'Failed to list users',
      message: error.message,
    });
  }
};

/**
 * Action: Assign user to coach group
 * Nếu user chưa tồn tại, tạo user mới và gửi email invite
 */
const assignCoach = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { email, username, name } = body;

    if (!email && !username) {
      return createResponse(400, {
        success: false,
        error: 'Email or username is required',
      });
    }

    // Use username if provided, otherwise use email as username
    const targetUsername = username || email;
    let userExists = true;
    let isNewUser = false;

    // Step 1: Check if user exists
    try {
      const getUserCommand = new AdminGetUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: targetUsername,
      });
      await cognitoClient.send(getUserCommand);
      console.log(`User ${targetUsername} already exists`);
    } catch (error) {
      if (error.name === 'UserNotFoundException') {
        userExists = false;
        console.log(`User ${targetUsername} not found, will create new user`);
      } else {
        throw error;
      }
    }

    // Step 2: If user doesn't exist, create new user
    if (!userExists) {
      console.log(`Creating new user: ${targetUsername}`);

      const userAttributes = [
        {
          Name: 'email',
          Value: email,
        },
        {
          Name: 'email_verified',
          Value: 'true', // Auto verify email for admin-created users
        },
      ];

      // Add name attribute if provided
      if (name) {
        userAttributes.push({
          Name: 'name',
          Value: name,
        });
      }

      const createUserCommand = new AdminCreateUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: targetUsername,
        UserAttributes: userAttributes,
        DesiredDeliveryMediums: ['EMAIL'], // Send email invite
        MessageAction: 'SUPPRESS', // We'll send custom email, or use default Cognito email
        // Remove MessageAction: 'SUPPRESS' to let Cognito send default invite email
      });

      // Actually, let Cognito send the invite email
      createUserCommand.input.MessageAction = undefined; // Use default Cognito email

      await cognitoClient.send(createUserCommand);
      isNewUser = true;
      console.log(`Created new user: ${targetUsername}`);
    }

    // Step 3: Add user to coach group
    const addToGroupCommand = new AdminAddUserToGroupCommand({
      UserPoolId: USER_POOL_ID,
      Username: targetUsername,
      GroupName: 'coach',
    });

    await cognitoClient.send(addToGroupCommand);
    console.log(`Added user ${targetUsername} to coach group`);

    // Return success with appropriate message
    return createResponse(200, {
      success: true,
      message: isNewUser
        ? `Đã tạo tài khoản coach mới cho ${email}. Email mời đã được gửi đến ${email}.`
        : `User ${targetUsername} đã được thêm vào nhóm coach`,
      username: targetUsername,
      email: email,
      isNewUser,
    });
  } catch (error) {
    console.error('Error assigning coach:', error);

    if (error.name === 'UsernameExistsException') {
      return createResponse(409, {
        success: false,
        error: 'Username already exists',
        message: 'User với email này đã tồn tại trong hệ thống',
      });
    }

    if (error.name === 'InvalidParameterException') {
      return createResponse(400, {
        success: false,
        error: 'Invalid parameters',
        message: error.message,
      });
    }

    return createResponse(500, {
      success: false,
      error: 'Failed to assign coach',
      message: error.message,
    });
  }
};

/**
 * Action: Remove user from coach group
 */
const removeCoach = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { email, username } = body;

    if (!email && !username) {
      return createResponse(400, {
        success: false,
        error: 'Email or username is required',
      });
    }

    const targetUsername = username || email;

    const command = new AdminRemoveUserFromGroupCommand({
      UserPoolId: USER_POOL_ID,
      Username: targetUsername,
      GroupName: 'coach',
    });

    await cognitoClient.send(command);

    return createResponse(200, {
      success: true,
      message: `User ${targetUsername} has been removed from coach group`,
      username: targetUsername,
    });
  } catch (error) {
    console.error('Error removing coach:', error);

    if (error.name === 'UserNotFoundException') {
      return createResponse(404, {
        success: false,
        error: 'User not found',
        message: error.message,
      });
    }

    return createResponse(500, {
      success: false,
      error: 'Failed to remove coach',
      message: error.message,
    });
  }
};

/**
 * Main Lambda Handler
 */
exports.handler = async (event) => {
  console.log('Admin Operations Lambda:', JSON.stringify(event, null, 2));

  // Handle OPTIONS for CORS preflight
  if (event.httpMethod === 'OPTIONS') {
    return createResponse(200, { message: 'OK' });
  }

  try {
    // Route based on HTTP method and path
    const method = event.httpMethod;
    const path = event.path || event.resource;

    // Public: allow customers/coaches to list coaches
    if (method === 'GET' && path.includes('coaches')) {
      return await listCoaches();
    }

    // Admin-only for remaining routes
    const authCheck = verifyAdminAccess(event);
    if (!authCheck.authorized) {
      return createResponse(403, {
        success: false,
        error: authCheck.error,
      });
    }

    // GET /coaches - List all coaches
    if (method === 'GET' && path.includes('coaches')) {
      return await listCoaches();
    }

    // GET /users - List all users
    if (method === 'GET' && path.includes('users')) {
      return await listUsers(event);
    }

    // POST /coaches - Assign user to coach group
    if (method === 'POST' && path.includes('coaches')) {
      return await assignCoach(event);
    }

    // DELETE /coaches - Remove user from coach group
    if (method === 'DELETE' && path.includes('coaches')) {
      return await removeCoach(event);
    }

    // Unknown route
    return createResponse(404, {
      success: false,
      error: 'Route not found',
      path,
      method,
    });
  } catch (error) {
    console.error('Unhandled error:', error);
    return createResponse(500, {
      success: false,
      error: 'Internal server error',
      message: error.message,
    });
  }
};
