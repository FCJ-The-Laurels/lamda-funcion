// Lambda: Customer list coaches (returns sub, email)
// Runtime: nodejs18.x+ uses AWS SDK v3 (built-in)
const { CognitoIdentityProviderClient, ListUsersInGroupCommand } = require('@aws-sdk/client-cognito-identity-provider');

// User Pool is in us-east-1, so client must target that region
const client = new CognitoIdentityProviderClient({ region: 'us-east-1' });

exports.handler = async (event) => {
  console.log('customer-list-coaches event:', JSON.stringify(event, null, 2));

  const userPoolId = process.env.USER_POOL_ID || 'us-east-1_dskUsnKt3';
  const groupName = process.env.COACH_GROUP || 'coach';
  const limit = parseInt(process.env.PAGE_SIZE || '60', 10);

  try {
    const query = event.queryStringParameters || {};
    const token = query.nextToken;

    const command = new ListUsersInGroupCommand({
      UserPoolId: userPoolId,
      GroupName: groupName,
      Limit: limit,
      NextToken: token || undefined,
    });

    const res = await client.send(command);

    const coaches = (res.Users || [])
      .map((u) => ({
        sub: u.Attributes?.find((a) => a.Name === 'sub')?.Value,
        email: u.Attributes?.find((a) => a.Name === 'email')?.Value,
      }))
      .filter((u) => u.sub);

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization,X-User-Id,X-User-Group',
      },
      body: JSON.stringify({
        coaches,
        nextToken: res.NextToken || null,
      }),
    };
  } catch (err) {
    console.error('Error listing coaches:', err);
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
      },
      body: JSON.stringify({ error: err.message || 'Internal error' }),
    };
  }
};

