import os
import time
import threading
import subprocess
from openai import OpenAI
from agents import Agent, Runner

def start_litellm_proxy():
    print("Starting LiteLLM proxy for AWS Bedrock...")
    # Start LiteLLM proxy pointing to Bedrock Haiku model
    # Requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION in env
    cmd = [
        "litellm",
        "--model", "bedrock/anthropic.claude-3-haiku-20240307-v1:0",
        "--port", "4000"
    ]
    proxy = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(3) # Wait for server to start
    return proxy

def get_weather(location: str):
    """Get the current weather in a given location."""
    # Dummy tool for the quickstart
    return f"The weather in {location} is 72 degrees and sunny."

if __name__ == "__main__":
    proxy = start_litellm_proxy()
    
    try:
        # Initialize OpenAI client pointing to LiteLLM proxy
        client = OpenAI(
            base_url="http://localhost:4000",
            api_key="dummy-key" # LiteLLM will use AWS credentials from env
        )

        my_agent = Agent(
            name="BedrockAssistant",
            instructions="You are a helpful assistant powered by AWS Bedrock (Claude 3 Haiku).",
            tools=[get_weather]
        )

        print("Agent is ready! (Type 'exit' to quit)")
        runner = Runner(agent=my_agent, client=client)
        
        while True:
            user_input = input("User: ")
            if user_input.lower() in ['exit', 'quit']:
                break
            
            response = runner.run(user_input)
            print(f"Agent: {response.final_output}")
            
    finally:
        print("Shutting down proxy...")
        proxy.terminate()
