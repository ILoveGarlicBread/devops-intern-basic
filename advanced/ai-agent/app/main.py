import os
import time
from openai import AsyncOpenAI
from agents import Agent, Runner, function_tool
from agents.models.openai_chatcompletions import OpenAIChatCompletionsModel

@function_tool
def get_weather(location: str):
    """Get the current weather in a given location."""
    return f"The weather in {location} is 72 degrees and sunny."

if __name__ == "__main__":
    print("Test CICD")
    print("Connecting natively to OpenAI...")
    
    # Securely pulling the API key injected by External Secrets Operator
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("WARNING: OPENAI_API_KEY environment variable is not set!")
        
    client = AsyncOpenAI(api_key=api_key)
    
    my_agent = Agent(
        name="OpenAIAssistant",
        instructions="You are a helpful assistant powered by OpenAI.",
        tools=[get_weather],
        model=OpenAIChatCompletionsModel(
            model="gpt-4o-mini", 
            openai_client=client
        )
    )
    
    print("Agent is ready! (Type 'exit' to quit)")
    runner = Runner()
    
    while True:
        try:
            user_input = input("User: ")
            if user_input.lower() in ['exit', 'quit']:
                break
            
            response = runner.run_sync(starting_agent=my_agent, input=user_input)
            print(f"Agent: {response.final_output}")
        except EOFError:
            break
