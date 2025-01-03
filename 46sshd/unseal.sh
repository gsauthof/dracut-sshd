#!/bin/sh

cd /etc/ssh

touch key ; chmod 600 key
tpm2_unseal -c key.ctx -p pcr:"$(cat pcrs)" -o key

for enc in *.enc; do
    base="${enc%.enc}"
    touch "$base" ; chmod 600 "$base"
    openssl aes-256-cbc -d -in "$enc" -out "$base" -kfile key -iter 1
done
