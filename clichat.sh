#!/bin/bash

# Check if GOOGLE_API_KEY is set
if [ -z "$GOOGLE_API_KEY" ]; then
    echo "Error: GOOGLE_API_KEY environment variable is not set."
    echo "Please set it using: export GOOGLE_API_KEY=your_api_key"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed."
    echo "Please install it using your package manager (apt, brew, yum, etc.)"
    exit 1
fi

# Create a temporary file to store conversation history
HISTORY_FILE=$(mktemp)

# Initialize conversation history as a JSON array
echo "[]" > "$HISTORY_FILE"

# Function to call Gemini API and stream the response
call_gemini_api() {
    local prompt="$1"
    local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=${GOOGLE_API_KEY}"
    
    # Add new user message to conversation
    jq '. += [{"role": "user", "parts": [{"text": "'"$prompt"'"}]}]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    
    # Prepare the request payload with full conversation history
    local payload='{
        "contents": '"$(cat "$HISTORY_FILE")"'
    }'
    
    # Create a temporary file for the response
    local response_file=$(mktemp)
    
    # Make the API call and process the streaming response
    curl "$api_url" \
        -s \
        -H 'Content-Type: application/json' \
        --no-buffer \
        -d "$payload" | while read -r line; do
            # Skip empty lines and metadata lines
            if [[ "$line" == data:* && "$line" != *"[DONE]"* ]]; then
                # Extract the text content from the JSON response
                content=$(echo "$line" | sed 's/^data: //g' | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
                if [ ! -z "$content" ]; then
                    printf "%s" "$content"
                    echo -n "$content" >> "$response_file"
                fi
            fi
        done
    
    # Read the full response from the temporary file
    local full_response=$(cat "$response_file")
    rm "$response_file"
    
    # Print a newline after the response for better formatting
    echo -e "\n"
    
    # Escape special characters in the response for JSON
    full_response=$(echo "$full_response" | jq -Rs .)
    
    # Remove the outer quotes that jq -Rs adds
    full_response="${full_response:1:-1}"
    
    # Add model response to conversation history
    jq '. += [{"role": "model", "parts": [{"text": "'"$full_response"'"}]}]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# Function to clean up temporary files on exit
cleanup() {
    rm -f "$HISTORY_FILE"
    exit 0
}

# Set trap to clean up on exit
trap cleanup EXIT

# Main loop to get user input and call the API
echo "Gemini API CLI with Conversation History (Press Ctrl+C to exit)"
echo "-------------------------------------------------------------"

while true; do
    echo -n "You: "
    read -r user_input
    
    # Skip if input is empty
    if [ -z "$user_input" ]; then
        continue
    fi
    
    echo "Gemini: "
    call_gemini_api "$user_input"
    echo "-------------------------------------------------------------"
done

