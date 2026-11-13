#!/bin/bash

# Download the project zip file
wget https://github.com/ytmcnet-byte/AA-project/raw/refs/heads/main/og-forward.zip

# Unzip the file
unzip og-forward.zip

# Navigate into the project directory
cd og-forward

# Make the start script executable
chmod +x start-server.sh

# Run the token command
npm run token

# Start the server in the background using nohup and log output
nohup ./start-server.sh >> server.log 2>&1 &

# Tail the log file to monitor output
tail -ف server.log
