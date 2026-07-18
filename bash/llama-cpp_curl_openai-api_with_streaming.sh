#!/bin/bash

# =========================================================================
#
# Sending request with prompt to local OpenAI API, echoing streaming
# response to terminal, and saving it to a file.
#
# =========================================================================

set -eu -o pipefail
# Uncomment for debug
# set -x

# =========================================================================
# NOTE:
# This file is prepared to be used with Shellcheck static analysis tool
# for shell scripts.
# =========================================================================

# =========================================================================
# Load external scripts
# =========================================================================

# shellcheck source=./helper_scripts/colors.sh
source ./helper_scripts/colors.sh

# =========================================================================
# Variable definitions
# =========================================================================

api_host="http://localhost:11434"
api_endpoint_models="/v1/models"
api_endpoint_chat="/v1/chat/completions"

model_1="gemma4:26b"
# Array used in check if defined models are present on target host
models_array=(
  "${model_1}"
)

# Set multi-line prompt
prompt_multi_line=$(
  cat <<EOF
Write a 1 verse poem about a blue bug
and a red bowl.
EOF
)

output_file="/tmp/llama-cpp-test-output-file.txt"

# =========================================================================
# Check if required packages are present in the system
# =========================================================================

command_name="curl"
if ! command -v ${command_name} &>/dev/null; then
  echo -e "${red}${command_name} not found - please install it${clear}"
  exit 1
fi

# =========================================================================
# Check if AI models are available
# =========================================================================

check_model_exists() {
  local model="$1"

  curl "${api_host}${api_endpoint_models}" \
    --no-progress-meter |
    jq -r '.data[].id' |
    grep -q '\b'"${model}"'\b'
}

echo "Sending request to API at: ${api_host}${api_endpoint_models}"

# Check if models are present, if not exit script
for model in "${models_array[@]}"; do
  if check_model_exists "${model}"; then
    echo -e "${green}Model ${model} found${clear}"
  else
    echo -e "${red}Error: Model ${model} not found${clear}"
    exit 1
  fi
done

echo -e "${green}Proceeding to the next step...${clear}"
echo

# =========================================================================
# Send request to local OpenAI API
# =========================================================================

echo "Sending request to API at: ${api_host}${api_endpoint_chat}"
echo -e "Using model: ${model_1}"

# Empty output file (later content is added by append with tee -a)
true >"${output_file}"

curl "${api_host}${api_endpoint_chat}" \
  --no-progress-meter \
  -H "Content-Type: application/json" \
  -d "$(
    jq -n --arg model "${model_1}" --arg prompt "${prompt_multi_line}" \
      '{
      "model": $model,
      "messages": [
        {
          "role": "user",
          "content": $prompt
        }
      ],
      # Line thinking_budget_tokens: 0 disables model thinking, comment this line if you want thinking
      # (comments are only allowed in jq filter language not in normal JSON)
      "thinking_budget_tokens": 0,
      "stream": true
    }'
  )" | while IFS= read -r line; do
  # Skip empty lines that are in response
  if [[ "${line}" == "data: "* ]]; then
    # Extract the JSON part (after 'data: ')
    json_data="${line#data: }"

    if [[ ${json_data} != "[DONE]" ]]; then

      # Print reasoning content if model thinking is enabled
      echo -ne "${yellow}"
      # Use jq '// empty' to handle null and "" gracefully
      echo "${json_data}" | jq -j '.choices[0].delta.reasoning_content // empty' 2>/dev/null | tee -a "${output_file}"
      echo -ne "${clear}"

      # Print response content
      echo -ne "${blue}"
      # Use jq '// empty' to handle null and "" gracefully
      echo "${json_data}" | jq -j '.choices[0].delta.content // empty' 2>/dev/null | tee -a "${output_file}"
      echo -ne "${clear}"
    fi
  fi
done

# Add new line at the end of the output file
echo >>"${output_file}"

echo -e "\n\nOutput file saved in: ${cyan}${output_file}${clear}"

# =========================================================================
# Script end
# =========================================================================

echo -e "\n${green}Script completed successfully.${clear}"
