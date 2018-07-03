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
