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
        os.environ["OPENAI_BASE_URL"] = "http://localhost:4000"
        os.environ["OPENAI_API_KEY"] = "dummy-key"
        
        my_agent = Agent(
            name="BedrockAssistant",
            instructions="You are a helpful assistant powered by AWS Bedrock (Claude 3 Haiku).",
            tools=[get_weather]
        )

        print("Agent is ready! (Type 'exit' to quit)")
        runner = Runner()
        
        while True:
            user_input = input("User: ")
            if user_input.lower() in ['exit', 'quit']:
                break
            
            response = runner.run_sync(starting_agent=my_agent, input=user_input)
            print(f"Agent: {response.final_output}")
            
    finally:
        print("Shutting down proxy...")
        proxy.terminate()
