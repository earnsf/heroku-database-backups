FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y curl unzip gpg

RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

RUN curl https://cli-assets.heroku.com/install.sh | sh

RUN mkdir /app

COPY bin/backup.sh /app


ENTRYPOINT ["bash"]
CMD	["-c","curl $HEALTHCHECK_URL"]
