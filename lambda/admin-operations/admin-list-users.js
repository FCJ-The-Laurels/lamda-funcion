// Lambda: Admin list all users (from all groups)
// Runtime: nodejs18.x - uses AWS SDK v3 (built-in)
const { CognitoIdentityProviderClient, ListUsersInGroupCommand } = require('@aws-sdk/client-cognito-identity-provider');

const cognito = new CognitoIdentityProviderClient({ region: 'us-east-1' });

exports.handler = async (event) => {
  console.log('admin-list-users event:', JSON.stringify(event, null, 2));

  const userPoolId = process.env.USER_POOL_ID || 'us-east-1_dskUsnKt3';
  const limit = parseInt(process.env.PAGE_SIZE || '60', 10);

  // CORS headers
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-User-Id,X-User-Group',
    'Content-Type': 'application/json',
  };

  try {
    const query = event.queryStringParameters || {};
    const token = query.nextToken;
    const groupFilter = query.group; // Optional: filter by group (customer, coach, admin)

    let allUsers = [];
    
    if (groupFilter) {
      // List users in specific group
      const command = new ListUsersInGroupCommand({
        UserPoolId: userPoolId,
        GroupName: groupFilter,
        Limit: limit,
        NextToken: token,
      });
      
      const res = await cognito.send(command);
      allUsers = (res.Users || []).map(u => mapUserAttributes(u, groupFilter));
      
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          users: allUsers,
          nextToken: res.NextToken || null,
        }),
      };
    } else {
      // List users from all groups
      const groups = ['customer', 'coach', 'admin'];
      
      for (const group of groups) {
        try {
          const command = new ListUsersInGroupCommand({
            UserPoolId: userPoolId,
            GroupName: group,
            Limit: 60, // Max allowed by Cognito
          });
          
          const res = await cognito.send(command);
          const groupUsers = (res.Users || []).map(u => mapUserAttributes(u, group));
          allUsers = allUsers.concat(groupUsers);
        } catch (err) {
          console.warn(`Failed to list ${group} group:`, err.message);
          // Continue with other groups
        }
      }
      
      // Remove duplicates (user might be in multiple groups)
      const uniqueUsers = [];
      const seenSubs = new Set();
      for (const user of allUsers) {
        if (!seenSubs.has(user.sub)) {
          seenSubs.add(user.sub);
          uniqueUsers.push(user);
        }
      }
      
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          users: uniqueUsers,
          total: uniqueUsers.length,
          nextToken: null, // No pagination for all groups
        }),
      };
    }
  } catch (err) {
    console.error('Error listing users:', err);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ error: err.message || 'Internal error' }),
    };
  }
};

/**
 * Map Cognito user attributes to frontend format
 */
function mapUserAttributes(cognitoUser, group) {
  const attrs = cognitoUser.Attributes || [];
  const getAttr = (name) => attrs.find(a => a.Name === name)?.Value;
  
  return {
    sub: getAttr('sub'),
    email: getAttr('email'),
    fullName: getAttr('name') || getAttr('given_name') || getAttr('email')?.split('@')[0] || 'User',
    phoneNumber: getAttr('phone_number'),
    emailVerified: getAttr('email_verified') === 'true',
    role: group?.toUpperCase() || 'CUSTOMER',
    status: cognitoUser.Enabled !== false ? 'ACTIVE' : 'INACTIVE',
    userStatus: cognitoUser.UserStatus, // CONFIRMED, UNCONFIRMED, etc.
    createdAt: cognitoUser.UserCreateDate,
    updatedAt: cognitoUser.UserLastModifiedDate,
    // These fields need to be fetched from User Service if needed
    tier: null,
    avatarUrl: null,
  };
}
