import subprocess
import json
import urllib.request
import os

# --- Configuration ---
# Pointing to a local Ollama instance to save tokens. 
# Change 'llama3' to whichever coding model you have pulled (e.g., 'codellama' or 'phi3').
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_NAME = "llama3"
<<<<<<< HEAD
BOARD_PATHS = [
    "Docs/Avelo_Release_Board.md",
    "Docs/Avelo_Execution_Checklist.md",
]
=======
BOARD_PATH = ".agents/TASK_BOARD.md"
>>>>>>> origin/main

def ask_local_llm(system_prompt, user_message):
    """Sends the task to your local LLM and returns the response."""
    print("🧠 Thinking...")
    payload = {
        "model": MODEL_NAME,
        "system": system_prompt,
        "prompt": user_message,
        "stream": False
    }
    
    req = urllib.request.Request(OLLAMA_URL, data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result.get("response", "")
    except Exception as e:
        return f"LLM Connection Error: Is Ollama running? ({e})"

def run_command(command):
    """Runs a terminal command like 'make test' and returns the output."""
    print(f"⚙️ Running: {command}")
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr

def read_file(filepath):
    """Reads a file's contents."""
    with open(filepath, 'r') as f:
        return f.read()

def main():
    print("🚀 Starting Avelo Autonomous Pipeline...")
    
<<<<<<< HEAD
    # 1. Read the canonical readiness board and executable queue.
    missing = [path for path in BOARD_PATHS if not os.path.exists(path)]
    if missing:
        print(f"Error: required canonical document(s) missing: {', '.join(missing)}")
        return
    board_content = "\n\n".join(
        f"# Source: {path}\n{read_file(path)}" for path in BOARD_PATHS
    )
=======
    # 1. Read the Task Board
    if not os.path.exists(BOARD_PATH):
        print(f"Error: {BOARD_PATH} not found.")
        return
    board_content = read_file(BOARD_PATH)
>>>>>>> origin/main
    
    # 2. Define the FLOW Agent's Brain
    flow_system_prompt = read_file(".agents/prompts/FLOW.md")
    
    # 3. Trigger FLOW
    print("\n--- 🤖 TRIGGERING FLOW AGENT ---")
    flow_directive = f"Here is the current board:\n{board_content}\nPlease execute the highest priority [FLOW] task and output the code/script updates."
    flow_response = ask_local_llm(flow_system_prompt, flow_directive)
    
    # Log the output
    with open(".agents/logs/FLOW_SCRIPTS.md", "a") as f:
        f.write(f"\n\n### Automated Run:\n{flow_response}")
    print("✅ FLOW task executed and logged.")

    # 4. Trigger TEST (Health Check)
    print("\n--- 🧪 TRIGGERING TEST AGENT (Build & Test) ---")
    return_code, test_output = run_command("make build && make test")
    
    if return_code == 0:
        print("✅ Build and Tests Passed! Handoff to QA ready.")
        # Here you would programmatically change [ ] to [x] in the markdown file
    else:
        print("❌ Build/Tests FAILED. Sending errors back to coder...")
        # In a full loop, you would pass `test_output` back to the LLM to fix the bug.
        with open(".agents/logs/STRESS_SCRIPTS.md", "a") as f:
            f.write(f"\n\n### Automated Test Failure:\n{test_output}")

if __name__ == "__main__":
<<<<<<< HEAD
    main()
=======
    main()
>>>>>>> origin/main
