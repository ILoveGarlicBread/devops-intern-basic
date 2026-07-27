from aws_bedrock_token_generator import provide_token
import requests

url = "https://bedrock-mantle.ap-south-1.api.aws/v1/models"
headers = {
    "Authorization": f"Bearer {provide_token()}"
}

response = requests.get(url, headers=headers)
print(response.json())
