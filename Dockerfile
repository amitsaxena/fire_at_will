# Use an official Ruby runtime as a base image
FROM ruby:2.3

# Set the working directory to /home/loadtest
WORKDIR /home/loadtest

# Install any needed packages
RUN gem install aws-sdk -v 2.9.39

# COPY ruby script and config
COPY load_test.rb .
COPY config/config.yml config/config.yml

# Copy .pem file to .ssh
COPY config/*.pem /root/.ssh/
RUN chmod 600 /root/.ssh/*.pem
