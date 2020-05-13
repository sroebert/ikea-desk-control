# See hooks/build and hooks/.config
ARG BASE_IMAGE_PREFIX
FROM ${BASE_IMAGE_PREFIX}node:12.10

# See hooks/post_checkout
ARG ARCH
COPY qemu-${ARCH}-static /usr/bin

# Install dependencies
RUN apt-get update && apt-get install -y \
  bluetooth \
  bluez \
  libbluetooth-dev \
  libudev-dev

# Setup App
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install
COPY . .

# Set ENV variables
ENV DATA_DIR /data
ENV CONFIG_FILE /data/config.json

# Start
CMD ["npm", "start"]
