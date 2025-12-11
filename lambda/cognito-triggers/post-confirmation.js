/**
 * Cognito Post Confirmation Lambda Trigger
 *
 * Trigger này được gọi sau khi user xác nhận email thành công.
 * Lambda sẽ:
 * 1. Tự động assign user vào group "customer" (nếu chưa có group)
 * 2. Gửi request tới User Service để tạo user profile (kèm role info)
 *
 * Trigger type: PostConfirmation
 * Trigger source: PostConfirmation_ConfirmSignUp
 */

const https = require('https');
const http = require('http');

// AWS SDK v3 - Import Cognito Identity Provider Client
// NOTE: Cần cài đặt: npm install @aws-sdk/client-cognito-identity-provider
let CognitoIdentityProviderClient, AdminAddUserToGroupCommand, AdminListGroupsForUserCommand;
let cognitoV2;
try {
  const cognitoModule = require('@aws-sdk/client-cognito-identity-provider');
  CognitoIdentityProviderClient = cognitoModule.CognitoIdentityProviderClient;
  AdminAddUserToGroupCommand = cognitoModule.AdminAddUserToGroupCommand;
  AdminListGroupsForUserCommand = cognitoModule.AdminListGroupsForUserCommand;
} catch (e) {
  console.log('AWS SDK v3 not found, trying v2 fallback for group assignment');
  try {
    cognitoV2 = require('aws-sdk');
  } catch (err) {
    console.log('AWS SDK v2 not available, group assignment will be skipped');
  }
}

// Configuration từ Environment Variables
const USER_SERVICE_URL = process.env.USER_SERVICE_URL || '';
const USER_SERVICE_API_KEY = process.env.USER_SERVICE_API_KEY || '';
const DEFAULT_USER_GROUP = process.env.DEFAULT_USER_GROUP || 'customer';
// Mặc định auto-assign vào group customer
const AUTO_ASSIGN_GROUP = process.env.AUTO_ASSIGN_GROUP
  ? process.env.AUTO_ASSIGN_GROUP === 'true'
  : true;
const AWS_REGION = process.env.AWS_REGION || 'ap-southeast-1';
const REQUEST_TIMEOUT_MS = parseInt(process.env.REQUEST_TIMEOUT_MS || '5000', 10);

const withTimeout = (promise, ms, label = 'operation') =>
  Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)
    ),
  ]);

/**
 * Lấy danh sách groups của user
 */
const getUserGroups = async (userPoolId, username) => {
  if (!CognitoIdentityProviderClient) {
    console.log('AWS SDK not available, skipping group fetch');
    return [];
  }

  try {
    const client = new CognitoIdentityProviderClient({ region: AWS_REGION });
    const command = new AdminListGroupsForUserCommand({
      UserPoolId: userPoolId,
      Username: username
    });

    const response = await client.send(command);
    const groups = response.Groups || [];
    return groups.map(g => g.GroupName);
  } catch (error) {
    console.error('Error fetching user groups:', error);
    return [];
  }
};

/**
 * Tự động assign user vào group mặc định
 */
const assignUserToDefaultGroup = async (userPoolId, username, groupName) => {
  // Try v3
  if (CognitoIdentityProviderClient) {
    try {
      const client = new CognitoIdentityProviderClient({ region: AWS_REGION });
      const command = new AdminAddUserToGroupCommand({
        UserPoolId: userPoolId,
        Username: username,
        GroupName: groupName
      });

      await client.send(command);
      console.log(`User assigned to group via SDK v3: ${groupName}`);
      return true;
    } catch (error) {
      console.error('Error assigning user to group (v3):', error);
    }
  }

  // Fallback v2
  if (cognitoV2) {
    try {
      const client = new cognitoV2.CognitoIdentityServiceProvider({ region: AWS_REGION });
      await client.adminAddUserToGroup({
        UserPoolId: userPoolId,
        Username: username,
        GroupName: groupName
      }).promise();
      console.log(`User assigned to group via SDK v2: ${groupName}`);
      return true;
    } catch (error) {
      console.error('Error assigning user to group (v2):', error);
    }
  }

  console.warn('Group assignment skipped: no AWS SDK available');
  return false;
};

/**
 * Gửi HTTP request tới User Service
 */
const sendHttpRequest = (url, options, data) => {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;

    const req = protocol.request(url, options, (res) => {
      let body = '';

      res.on('data', (chunk) => {
        body += chunk;
      });

      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({
            statusCode: res.statusCode,
            body: body
          });
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${body}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    // Timeout cấu hình (mặc định 5 giây) để tránh Lambda bị treo
    req.setTimeout(REQUEST_TIMEOUT_MS, () => {
      req.destroy(new Error('Request timeout'));
    });

    if (data) {
      req.write(JSON.stringify(data));
    }

    req.end();
  });
};

/**
 * Tạo user profile trong User Service
 */
const createUserProfile = async (userData) => {
  if (!USER_SERVICE_URL) {
    console.warn('USER_SERVICE_URL not configured. Skipping user profile creation.');
    return;
  }

  const url = `${USER_SERVICE_URL}/api/users`;

  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': USER_SERVICE_API_KEY
    }
  };

  console.log('Creating user profile:', JSON.stringify(userData, null, 2));

  try {
    const response = await sendHttpRequest(url, options, userData);
    console.log('User profile created successfully:', response.body);
    return response;
  } catch (error) {
    console.error('Failed to create user profile:', error);
    throw error;
  }
};

/**
 * Main Lambda handler
 */
exports.handler = async (event) => {
  console.log('Cognito Post Confirmation Trigger:', JSON.stringify(event, null, 2));

  try {
    // Tránh chờ event loop làm Lambda treo
    if (typeof event?.context === 'object') {
      event.context.callbackWaitsForEmptyEventLoop = false;
    }
    if (typeof global !== 'undefined' && global.callbackWaitsForEmptyEventLoop !== undefined) {
      global.callbackWaitsForEmptyEventLoop = false;
    }

    // Extract user data từ Cognito event
    const { request, userName, userPoolId } = event;
    const userAttributes = request.userAttributes;

    // Step 1: Tự động assign user vào group mặc định (customer)
    if (AUTO_ASSIGN_GROUP) {
      console.log(`Auto-assigning user to group: ${DEFAULT_USER_GROUP}`);
      const ok = await withTimeout(
        assignUserToDefaultGroup(userPoolId, userName, DEFAULT_USER_GROUP),
        REQUEST_TIMEOUT_MS,
        'assignUserToDefaultGroup'
      );
      if (!ok) {
        throw new Error('Failed to assign user to default group');
      }
    }

    // Step 2: Lấy danh sách groups của user
    const userGroups = await getUserGroups(userPoolId, userName);
    console.log('User groups:', userGroups);

    // Xác định role (lấy group có precedence cao nhất, hoặc default)
    const role = userGroups.length > 0 ? userGroups[0] : DEFAULT_USER_GROUP;

    // Step 3: Chuẩn bị data để gửi tới User Service
    const userData = {
      cognitoUserId: userName, // Cognito user ID (sub)
      email: userAttributes.email,
      emailVerified: userAttributes.email_verified === 'true',

      // Custom attributes từ Cognito (nếu có)
      name: userAttributes.name || '',
      phone: userAttributes.phone_number || '',
      dateOfBirth: userAttributes.birthdate || null,
      gender: userAttributes.gender || null,

      // Role & Groups (RBAC)
      role: role, // Primary role
      groups: userGroups, // All groups user belongs to

      // Metadata
      userPoolId: userPoolId,
      createdAt: new Date().toISOString(),
      source: 'cognito_post_confirmation'
    };

    // Step 4: Gửi request tới User Service để tạo profile
    await withTimeout(createUserProfile(userData), REQUEST_TIMEOUT_MS, 'createUserProfile');

    console.log('Successfully processed post confirmation trigger');

    // QUAN TRỌNG: Phải return event object để Cognito tiếp tục flow
    return event;

  } catch (error) {
    console.error('Error processing post confirmation trigger:', error);

    // OPTION 1: Throw error - User sẽ không được confirm (recommended cho production)
    // throw new Error('Failed to create user profile');

    // OPTION 2: Return event - User vẫn được confirm dù tạo profile thất bại
    // Bạn có thể xử lý retry logic sau
    console.warn('Returning event despite error to allow user confirmation');
    return event;
  }
};
