#!/bin/sh
curl -L https://github.com/AccessKit/accesskit-c/releases/download/0.13.0/accesskit-c-0.13.0.zip -o accesskit-c-0.13.0.zip && \
rm -rf accesskit-c-0.13.0 && \
unzip accesskit-c-0.13.0.zip && \
rm accesskit-c-0.13.0.zip
