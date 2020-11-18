# cli-mfa
This repository contains notes and tools for dealing with MFA using the AWS CLI. The documentation around this is quite good, but scattered, and it's difficult to get a handle on how to use the various facilities effectively. These materials are particularly framed from a DevSecOps viewpoint, with an emphasis on how these facilities affect securely configuring and maintaining the AWS infrastructure, rather than using the infrastructure.

At a high level, it's possible that the optimal way to use the AWS CLI is from an EC2 instance within the environment with an appropriate instance role attached. This does pose the problem that you then need to be concerned with controlling access to that instance, and the audit trail of API calls will record the instance as the principal in calls, rather than the actual user.

There is another complication with that scenario - in order to maintain the instance, and probably IAM assets around it's access, you need to operate from outside the instance itself, probably from an administrator or developer's computer.

Providing a fairly high level of access for a principal to act off their computer is a risky proposition. If you are willing to operate purely through the AWS console, then you can require MFA in addition to the user ID / password pair. We're interested though in good DevSecOps practices, and doing things manually through the console are not best practice.

## CLI Use

There are alternatives to the simple in-built facilities provided by the AWS CLI tool, which we'll deal with separately.

At the base of authentication for the AWS CLI are the CLI configuration files. This is documented reasonably well at <https://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html>, which is a good place to start. There are a handful of important points that are not necessarily obvious:

 - You can put credentials in the the `~/.aws/config` file, but it's not recommended, and `~/.aws/credentials` takes precedence over `~/.aws/config`.
 - credentials in the `credentials` file are tagged with `[name]`, but `config` entries tagged with `[profile name]`
 - `[default]` config applies to all profiles unless overridden, `[default]` credential is the default principal identifier
 - `$AWS_PROFILE` can be used to specify a profile rather than passing it at as a CLI parameter
 - `$AWS_ACCESS_KEY_ID` and `$AWS_SECRET_ACCESS_KEY` override entries in config files, and you can use `$AWS_SESSION_TOKEN` - see <https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html>

Storing credentials in the `~/.aws/credentials` file is quite risky - it's good practice to ensure that directory and it's contents are only readable by the owner, however the credentials are in plain text, so if the computer is compromised they should be considered to be breached. If the simple credential pair can be further constrained using MFA, the security risk is significantly reduced.

The documentation around using MFA for IAM credentials is not well organised, but it is complete, as long as you can find it:
 - [Overview](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html)
 - [Setting Up MFA programmatically](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_cliapi.html)
 - [Using MFA with CLI](https://aws.amazon.com/premiumsupport/knowledge-center/authenticate-mfa-cli/)
 - [Temporary Credential Limitations](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_request.html#stsapi_comparison)

The first half of the solution is quite simple: you make a call to the `STS` service to obtain temporary credentials that can be used for other API calls:
```
$ aws sts get-session-token --serial-number arn:aws:iam::931304388919:mfa/devuser --token-code 150355
{
  "Credentials": {
    "SecretAccessKey": "GS+uUxUeBJ0f7wnFTLP8+C0nTO/iEe5cuFMMj6Lc",
    "SessionToken": "FQoDYXdzEFsaDEBVOb7NNZ0WL0g5xCKwATh8Yo+p0XJQDwO5iMrEd9ajopwuK9ZFK7V61it/e+JrK0RQvgyAedB9R5n7r/fXHg/Ak6YACe9DtlhVpX8Ww8VWbxlMibruc4/DtZKXT8n7UbREfFAnl1rhSD18iFUd39uuuu1dOVtqYwJUob7MzUUMs3vypk66ARWyHcd1H+S0PgnnUbN/ynvhq+BREtEgBX4UIrbxByzYskSC2x6v8oDnrCj+9HHgKGICm/Yj6f0LKIOI7dkF",
    "Expiration": "2018-07-03T21:38:11Z",
    "AccessKeyId": "ASIAJCOAUNBB4H4BZRIQ"
  }
 }
```

The two parameters explicitly passed to the call are the identifier of the MFA device associated with the principal, and the current token displayed by the device. The values returned in the chunk of JSON can then be used for further calls, but it's a nuisance. Either environmental variables are set:

 - $AWS_ACCESS_KEY_ID == _Credentials.AccessKeyId_
 - $AWS_SECRET_ACCESS_KEY == _Credentials.SecretAccessKey_
 - $AWS_SESSION_TOKEN == _Credentials.SessionToken_

or they can be set in the credentials file and used as a profile:

```
[temp]
aws_access_key_id=ASIAJCOAUNBB4H4BZRIQ
aws_secret_access_key=GS+uUxUeBJ0f7wnFTLP8+C0nTO/iEe5cuFMMj6Lc
aws_session_token=FQoDYXdzEFsaDEBVOb7NNZ0WL0g5xCKwATh8Yo+p0XJQDwO5iMrEd9ajopwuK9ZFK7V61it/e+JrK0RQvgyAedB9R5n7r/fXHg/Ak6YACe9DtlhVpX8Ww8VWbxlMibruc4/DtZKXT8n7UbREfFAnl1rhSD18iFUd39uuuu1dOVtqYwJUob7MzUUMs3vypk66ARWyHcd1H+S0PgnnUbN/ynvhq+BREtEgBX4UIrbxByzYskSC2x6v8oDnrCj+9HHgKGICm/Yj6f0LKIOI7dkF
```

At a glance this looks pretty useful - you've got some credentials with a fixed life span even if it's a bit fiddly to get them in play for subsequent CLI calls. Note you can specify a shorter lifespan, as the default is quite long - see <https://docs.aws.amazon.com/cli/latest/reference/sts/get-session-token.html> for more information.

There's some problems though.

To begin with you cannot use the temporary credentials to use the IAM or STS API (see <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_control-access_getsessiontoken.html>). More critically, you still had to have provided credentials for the IAM user in order to be able to request the temporary credential. It's not particularly obvious, but does need to be spelled out: even though you have different credentials, you still operate as the same principal, although all subsequent calls carry an indication that MFA has been enabled.

This does suggest one route forward - the user (or better the user's group) - could have a policy that allowed calling _GetSessionToken_ without restriction, but then require MFA to be enabled for any other actions. This is feasible if the principal has a fairly limited set of permissions, but could get cumbersome for an administration or development account.

The `mfa.sh` script is one possible way of making obtaining and using the token a little less cumbersome. Note this is just a sketch, the ARN of the MFA key is hard-wired, which is sub-optimal. Nevertheless, invoking the script with the MFA session token will parse the JSON and launch a new shell with the appropriate environmental variables set to overload whatever credentials are specified in the files.

It's useful when testing this to look at the CloudTrail logs to verify that you wind up with the expected principal - in my case I could see the expected snippet:

```
"userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAI2O37N4DXSYCLZBW2",
    "arn": "arn:aws:iam::931304388919:user/devuser",
    "accountId": "931304388919",
    "accessKeyId": "ASIAJCOAUNBB4H4BZRIQ",
    "userName": "devuser",
    "sessionContext": {
        "attributes": {
            "mfaAuthenticated": "true",
            "creationDate": "2018-07-03T14:24:39Z"
        }
    }
},
```

## Hashicorp Vault
[Hashicorp Vault](https://www.vaultproject.io) is a very interesting option. Bearing in mind that we would like to not have Access Key/Secret Key pairs on the desktop, Vault provides a way in which short-lived credentials can be obtained for use then discarded, without needing access keys on the desktop at any point. I strongly recommend that you read the [introduction](https://www.vaultproject.io/intro) materials for Vault, as it's an elegant but complex tool that should be approached carefully.

At a high level part of Vault is functionally similar to [Secrets Manager](https://aws.amazon.com/secrets-manager/) - a way to securely hold encrypted secrets held as key/value pairs. It provides quite a bit more functionality though, and that is where the complexity arises. In the following examples I run a `vault` server instance locally in development mode (note also I'm using version 0.10.2), but this is _very_ definitely not a recommended practice for anything other than testing as we are doing here. `vault` is intended to run as a service, and one best practice is to run it with a [Consul](https://www.consul.io) back end. In this scenario, Vault will make use of Consul as a storage engine, rather than managing it's own storage. The big advantage here is that it's quite straightforward to build a highly-available, highly-resilient Consul cluster, and as a result fairly easy to set Vault up as a high-available, highly-resilient service.

It should be emphasised that in a production environment, using the `vault` server would require provision of authentication keys - generally a userid/password pair, although more complex authentication backends can be built (see <https://www.vaultproject.io/docs/auth/index.html>). The `vault` enterprise mode also supports MFA for calling the server. In addition, the `vault` server has a rich language for expressing policies around how authentication principals can use it, however this is an independent realm of authorisation and authentication outside AWS and whatever the backend authentication service provides, and decidedly non trivial. None of that is dealt with below, you should assume that the activity of setting up and configuring `vault` is independent of setting up and configuring the rest of your AWS infrastructure. I would highly recommend that the service be set up in an independent and dedicated VPC, or even AWS account.

The advantage in using `vault` to obtain short-lived AWS credentials is that the individual CLI users do not ever have to have their own user accounts, or their own AWS access keys, reducing the risk of those keys leaking considerably. There is also an advantage for security administrators: `vault` provides means to easily and quickly disable individual access, or to break the glass and seal access to secrets entirely.

Before proceeding, you will need to [download](https://www.vaultproject.io/downloads.html) and install Vault. All the work shown below was using version 0.10.2. The `vault` executable can be placed anywhere in the shell path as desired.

To begin with, in one shell, we start up a `vault` server in development mode. Again, this is _not_ suitable in any way for production use - among other things any stored secrets or configuration will be discarded when the server terminates:

```
vault server -dev
```

This starts up the local server in dev mode listening on port 8200, so we go to another shell to be able to work with it:

```
$ export VAULT_ADDR=http://127.0.0.1:8200
$ vault status
Key             Value
---             -----
Seal Type       shamir
Sealed          false
Total Shares    1
Threshold       1
Version         0.10.2
Cluster Name    vault-cluster-0ef7d3d6
Cluster ID      aaa2e1c4-b22f-2278-1f20-5f501297348d
HA Enabled      false
```

Vault uses various "secrets engines" to provide glue to other backends, such as AWS IAM. In general terms the `vault` API is somewhat RESTful, mainly using `read` and `write` to store and fetch secrets. Another useful analogy is to think of `vault` as following filesystem semantics, with different secrets engines mounted at different points in the file system tree - much of the Vault documentation talks of it as a virtual filesystem.

In order to use the IAM backend, we add the secrets engine, and provide credentials that the server will use on our behalf. Fairly obviously this would be done in production as the service was installed and configured. Note also that it's reasonably sane to store the credentials in the `vault` server, as the server's encryption is rock solid.

```
$ vault secrets enable aws
Success! Enabled the aws secrets engine at: aws/

$ vault write aws/config/root \
    access_key=AKIAJWVN5Z4FOFT7NLNA \
    secret_key=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 \
    region=eu-west-2
Success! Data written to: aws/config/root

$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
aws/          aws          aws_320d6b0a          n/a
cubbyhole/    cubbyhole    cubbyhole_05da00be    per-token private secret storage
identity/     identity     identity_0f9eb80f     identity store
secret/       kv           kv_a7784dfb           key/value secret storage
sys/          system       system_621e812d       system endpoints used for control, policy and debugging
```

A best practice here would be to create a specific Vault IAM user, with a carefully constructed policy attached, or alternatively to run the `vault` server on an EC2 instance with the appropriate role attached, bearing in mind the caveat from the documentation.

> Internally, Vault will connect to AWS using these credentials. _As such, these credentials must be a superset of any policies which might be granted on IAM credentials._ Since Vault uses the official AWS SDK, it will use the specified credentials. You can also specify the credentials via the standard AWS environment credentials, shared file credentials, or IAM role/ECS task credentials. (Note that you can't authorize vault with IAM role credentials if you plan on using STS Federation Tokens, since the temporary security credentials associated with the role are not authorized to use GetFederationToken.)

The import of this may not be immediately obvious - we can avoid storing the configuration inside `vault` if the `vault` service is running in an environment where the AWS SDK is able to find the credentials.

The [documentation](https://www.vaultproject.io/docs/secrets/aws/index.html) discusses the various policies and permissions that the server needs. The basic use case though is the one we are interested in: providing CLI access on the desktop while protecting access keys. There are two broad patterns of use. In the first case, Vault will create dummy IAM users on our behalf, with directly assigned policies, either using an inline policy (refer to the https://www.vaultproject.io/docs/secrets/aws/index.html for an example), or a policy ARN:

```
$ vault write aws/roles/ec2readonly arn=arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
Success! Data written to: aws/roles/ec2readonly
```

This policy or role is held entirely within `vault`, and should not be confused with the IAM rule and policy - we store the policy in the `vault` service, and `vault` uses it when it makes the appropriate IAM calls.

Having set up a role, we can make a read call against the AWS secrets engine to get an access/secret pair to use against AWS with that role:

```
$ vault read aws/creds/ec2readonly
Key                Value
---                -----
lease_id           aws/creds/ec2readonly/3751b993-133b-8cf8-0b7d-b87527a9e4f4
lease_duration     768h
lease_renewable    true
access_key         AKIAJEZBHAZJ3XOZLVSQ
secret_key         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
security_token     <nil>

$ export AWS_ACCESS_KEY_ID=AKIAJEZBHAZJ3XOZLVSQ
$ export AWS_SECRET_ACCESS_KEY=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
$ aws ec2 describe-instances
{
    "Reservations": []
}
```

Please note:

> Each invocation of the command will generate a new credential. Unfortunately, IAM credentials are eventually consistent with respect to other Amazon services. If you are planning on using these credential in a pipeline, you may need to add a delay of 5-10 seconds (or more) after fetching credentials before they can be used successfully.

In a different shell, with appropriate credentials (or using the AWS console), we can see that a dummy user has been created (details omitted in this example)

```
$ aws iam list-users
{
    "Users": [
        {
            "UserName": "vault-root-ec2readonly-1532257268-6823",
            "Path": "/",
            "CreateDate": "2018-07-22T11:01:09Z",
            "UserId": "AIDAJBDK2BH7OPAM6XSDE",
            "Arn": "arn:aws:iam::889199313043:user/vault-root-ec2readonly-1532257268-6823"
        }
    ]
}

$ aws iam  list-attached-user-policies --user-name vault-root-ec2readonly-1532257268-6823
{
    "AttachedPolicies": [
        {
            "PolicyName": "AmazonEC2ReadOnlyAccess",
            "PolicyArn": "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
        }
    ]
}
```

returning to the first shell, revoke the lease and drop the local credentials
```
$ vault lease revoke aws/creds/ec2readonly/3751b993-133b-8cf8-0b7d-b87527a9e4f4
Success! Revoked lease: aws/creds/ec2readonly/3751b993-133b-8cf8-0b7d-b87527a9e4f4

$ aws ec2 describe-instances
An error occurred (AuthFailure) when calling the DescribeInstances operation: AWS was not able to validate the provided access credentials

$ unset AWS_ACCESS_KEY_ID
$ unset AWS_SECRET_ACCESS_KEY
```

and we can see that the user is now gone:

```
$ aws iam get-user --user-name vault-root-ec2readonly-1532257268-6823
An error occurred (NoSuchEntity) when calling the GetUser operation: The user with name vault-root-ec2readonly-1532257268-6823 cannot be found.
```

You should be able to see that the temporary user has been destroyed.

There are alternative mechanisms available to avoid this creation of a temporary user, via the STS api. This is accessed via a write, and my initial thought was that we can re-use the same policy:

```
$ vault write aws/sts/ec2readonly ttl=60m
Error writing data to aws/sts/ec2readonly: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/aws/sts/ec2readonly
Code: 400. Errors:

* Can't generate STS credentials for a managed policy; use a role to assume or an inline policy instead
```

This is annoying, as it means we need to set up an inline policy instead which is functionally equivalent to the managed policy (see `ec2readonly.json`). Here we overwrite the one we had previously, then make a call to obtain a session token from the STS api.

```
$ vault write aws/roles/ec2readonly policy=@ec2readonly.json
Success! Data written to: aws/roles/ec2readonly

$ vault write aws/sts/ec2readonly ttl=60m
Key                Value
---                -----
lease_id           aws/sts/ec2readonly/96f497e4-5ddb-ea9f-902b-1b923e17ca6b
lease_duration     59m59s
lease_renewable    false
access_key         ASIA46CDIYCJ3ZTW3A5A
secret_key         Va4AGaTpMWQKbgXyHacY5NB7P3B7rHmvksMXZGrL
security_token     FQoDYXdzEEUaDLFkooYUHgcczMReFCLGAluxi6AjoQOXkujrdlpkoMXzNXbR8lw...

$ export AWS_ACCESS_KEY_ID=ASIA46CDIYCJ3ZTW3A5A
$ export AWS_SECRET_ACCESS_KEY=Va4AGaTpMWQKbgXyHacY5NB7P3B7rHmvksMXZGrL
$ export AWS_SESSION_TOKEN=FQoDYXdzEEUaDLFkooYUHgcczMReFCLGAluxi6AjoQOXkujrdlpkoMXzNXbR8lw...

$ aws ec2 describe-instances
{
    "Reservations": []
}

$ aws sts get-caller-identity
{
    "Account": "889199313043",
    "UserId": "889199313043:vault-1532260548-5040",
    "Arn": "arn:aws:sts::889199313043:federated-user/vault-1532260548-5040"
}

```

It will take a while - allow about 10 minutes - for the trace of the `describe-instances` to show up in CloudTrail, but when it does you will be able to confirm the identity of the caller:

```
{
    "eventVersion": "1.05",
    "userIdentity": {
        "type": "FederatedUser",
        "principalId": "889199313043:vault-1532260548-5040",
        "arn": "arn:aws:sts::889199313043:federated-user/vault-1532260548-5040",
        "accountId": "889199313043",
        "accessKeyId": "ASIA46CDIYCJ3ZTW3A5A",
        "sessionContext": {
            "attributes": {
                "mfaAuthenticated": "false",
                "creationDate": "2018-07-22T11:55:48Z"
            },
            "sessionIssuer": {
                "type": "IAMUser",
                "principalId": "AIDAJVOFC6DLBWBOLOE54",
                "arn": "arn:aws:iam::889199313043:user/XXXXXX",
                "accountId": "889199313043",
                "userName": "XXXXXX"
            }
        }
    },
    "eventTime": "2018-07-22T12:02:50Z",
    "eventSource": "ec2.amazonaws.com",
    "eventName": "DescribeInstances",
    "awsRegion": "eu-west-2",
    "sourceIPAddress": "88.98.207.26",
    "userAgent": "aws-cli/1.15.40 Python/2.7.10 Darwin/17.7.0 botocore/1.10.40",
    "requestParameters": {
        "instancesSet": {},
        "filterSet": {}
    },
    "responseElements": null,
    "requestID": "69d4b320-8bd2-462a-92a1-6d1007b9a8e0",
    "eventID": "a96a6165-4bb8-484d-8db8-b4eb75f78901",
    "eventType": "AwsApiCall",
    "recipientAccountId": "889199313043"
}
```

Experimentation showed that the STS token remains useable even after you do a `vault lease revoke`, suggesting that if this mechanism is used, a short TTL should be used.

A similar mechanism from the point of view of the caller is available (see https://www.vaultproject.io/docs/secrets/aws/index.html) where instead of using an in-line policy, a role is assumed. This is somewhat nicer, as it ensures the operating policy is visible purely within AWS - using the STS mechanism outlined above, the policy document is held in `vault` and used when acquiring the token, after which the caller and the policy it is operating with are effectively invisible and anonymous.

One trouble with both mechanisms is that the identity of the actual caller gets lost - the identity of the user on the laptop is not easily visible. If an appropriate authentication back end was put in place for the `vault` server, and the audit trail periodically captured, it becomes possible to ensure that only authorised users can obtain AWS credentials, and to see who obtained credentials when.

Ideally, using `vault` to provide credentials should be configured so that different users, and/or temporary credentials, map onto different AWS operating policies. Doing this is non-trivial and somewhat tricky, and your needs will be unique. In many regards, use of `vault` to obtain AWS credentials is probably more use for scripts rather than ad-hoc CLI use, in which case the question arises as to why those scripts are not being run from authorised EC2 instances rather than the desktop. It feels like `vault` is most useful for the case where we need privileged users to be bootstrapping up AWS infrastructure in a controlled fashion, after which further configuration and maintenance is done from within AWS via privileged EC2 instances. There are several layers of "bootstrapping" in play in this scenario, as there would need to be an initial phase around setting up the `vault` service itself!

On a final note, in the examples above, the `vault` program is being used as the client for the running `vault` server. This has some drawbacks, as the output is by default designed for human readability. It's possible to specify the output to be in JSON, which would allow the JSON to then be parsed by `jq` or similar:

```
$ export VAULT_FORMAT=json
$ vault write aws/sts/ec2readonly ttl=60m
{
  "request_id": "725cbf75-2737-685a-e7c5-ca689a933ee7",
  "lease_id": "aws/sts/ec2readonly/fe77b067-fefd-afb8-8bd1-4fb956933692",
  "lease_duration": 3599,
  "renewable": false,
  "data": {
    "access_key": "ASIA46CDIYCJX5F73F7K",
    "secret_key": "+yjSBdAYpcNAT912lbCCJI0kCSIOFDHasKr710pP",
    "security_token": "FQoDYXdzEEYaDJSAudTfP2BXDAsfiy..."
  },
  "warnings": null
}
```

Alternatively, the `vault` server has a RESTful HTTP API which could be used effectively in scripts, although the semantics of the `vault` client are probably more transparent.

### Automating Vault Configuration
Configuring vault is well outside the scope of this current work, however the following article from Hashicorp has some useful starting thoughts: <https://www.hashicorp.com/blog/codifying-vault-policies-and-configuration>. Another article worth looking at discusses using Terraform to configure Vault, pointing out that the Hashicorp suggestion is only really useful for additive changes, whereas because Terraform is stateful you may be able to get a happier experience with it: <https://theartofmachinery.com/2017/07/15/use_terraform_with_vault.html>. Note that this article does not encompass setting up a `vault` cluster, just provisioning of configurations into it.

In either of these cases, it cannot be emphasised enough: the actual secrets should still be added to `vault` manually. There are other issues around integrating Terraform and Vault that need to be considered, this article is a starting point: <https://www.greenreedtech.com/mitigating-terraform-secrets-exposure/>. It includes suggestions around mitigating the risks, but the bottom line is that while you might use Terraform to set up and configure `vault`, reading and writing secrets with [Terraform](https://www.terraform.io/docs/providers/vault/index.html) is currently not a good idea.


## License
Copyright 2018 Leap Beyond Emerging Technologies B.V.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
