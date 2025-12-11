// Lambda: Admin add user to coach group
// Runtime: nodejs18.x (or higher), uses AWS SDK v2 built-in
const AWS = require('aws-sdk');
const cognito = new AWS.CognitoIdentityServiceProvider();

exports.handler = async (event) => {
  console.log('admin-add-coach event:', JSON.stringify(event, null, 2));

  const userPoolId = process.env.USER_POOL_ID || 'us-east-1_dskUsnKt3';
  const groupName = process.env.COACH_GROUP || 'coach';

  try {
    // Parse body
    const body = JSON.parse(event.body || '{}');
    const username = body.username || body.sub;
    if (!username) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'username (sub) is required' }),
      };
    }

    await cognito.adminAddUserToGroup({
      GroupName: groupName,
      UserPoolId: userPoolId,
      Username: username,
    }).promise();

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: `Added ${username} to group ${groupName}`,
      }),
    };
  } catch (err) {
    console.error('Error adding coach:', err);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message || 'Internal error' }),
    };
  }
};

