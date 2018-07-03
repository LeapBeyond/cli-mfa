#!/bin/bash

[ "$#" -lt 1 ] && echo "`basename $0` Usage: `basename $0` mfatoken"

ARN=arn:aws:iam::313043889199:mfa/devuser

aws sts get-session-token --serial-number $ARN --token-code $1 --output json > /tmp/$$.json

export AWS_SECRET_ACCESS_KEY=$(grep SecretAccessKey /tmp/$$.json | cut -f4 -d'"')
export AWS_ACCESS_KEY_ID=$(grep AccessKeyId /tmp/$$.json | cut -f4 -d'"')
export AWS_SESSION_TOKEN=$(grep SessionToken /tmp/$$.json | cut -f4 -d'"')

rm /tmp/$$.json
/bin/bash
