import boto3
import datetime

def lambda_handler(event, context):
    # This connects to your Mumbai resources
    ec2 = boto3.client('ec2', region_name='ap-south-1')
    
    # Get the current time in UTC
    now = datetime.datetime.now()
    current_hour = now.hour
    current_minute = now.minute
    
    print(f"Current UTC Time: {current_hour}:{current_minute:02d}")

    # Find instances that have our specific tags
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag-key', 'Values': ['AutoStop', 'AutoStart']},
            {'Name': 'instance-state-name', 'Values': ['running', 'stopped']}
        ]
    )

    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            id = instance['InstanceId']
            state = instance['State']['Name']
            
            # Extract tags to verify what this specific instance is allowed to do
            tags = {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}
            
            # --- TESTING BLOCK ---
            # Change these numbers to 2 or 3 minutes from now (in UTC time) to test it live!
            TARGET_TEST_HOUR = 2
            TARGET_TEST_MINUTE = 35
            
            if current_hour == TARGET_TEST_HOUR and current_minute == TARGET_TEST_MINUTE:
                if state == 'stopped' and 'AutoStart' in tags:
                    print(f"Match found! Starting {id}...")
                    ec2.start_instances(InstanceIds=[id])
            # ---------------------

            # Evening Stop Rule (Standard Production Schedule: 11:00 UTC)
            elif current_hour == 11 and current_minute == 0 and state == 'running' and 'AutoStop' in tags:
                print(f"Scheduled Evening Stop: Stopping {id}...")
                ec2.stop_instances(InstanceIds=[id])
            
            # Morning Start Rule (Standard Production Schedule: 01:30 UTC)
            elif current_hour == 1 and current_minute == 30 and state == 'stopped' and 'AutoStart' in tags:
                print(f"Scheduled Morning Start: Starting {id}...")
                ec2.start_instances(InstanceIds=[id])

