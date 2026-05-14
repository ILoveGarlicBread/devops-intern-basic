import boto3
import datetime

def lambda_handler(event, context):
    # This connects to your Mumbai resources
    ec2 = boto3.client('ec2', region_name='ap-south-1')
    
    # Get the current hour in UTC (AWS time)
    # 8:30 AM VN is 01:30 UTC | 6:00 PM VN is 11:00 UTC
    now = datetime.datetime.now()
    current_hour = now.hour
    
    print(f"Current UTC Hour: {current_hour}")

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
            
            # Logic: If it's evening (11 UTC), stop it. If it's morning (01 UTC), start it.
            if current_hour >= 11 and state == 'running':
                print(f"Stopping {id} to save money...")
                ec2.stop_instances(InstanceIds=[id])
            
            elif current_hour >= 1 and current_hour < 11 and state == 'stopped':
                print(f"Starting {id} for the workday...")
                ec2.start_instances(InstanceIds=[id])           
