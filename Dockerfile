FROM localstack/java-maven-node-python

MAINTAINER Waldemar Hummer (waldemar.hummer@gmail.com)
LABEL authors="Waldemar Hummer (waldemar.hummer@gmail.com), Gianluca Bortoli (giallogiallo93@gmail.com)"

# install basic tools
RUN pip install awscli awscli-local requests --upgrade
RUN apk add iputils

# add files required to run "make install"
ADD Makefile requirements.txt ./
RUN mkdir -p localstack/utils/kinesis/ && mkdir -p localstack/services/ && \
  touch localstack/__init__.py localstack/utils/__init__.py localstack/services/__init__.py localstack/utils/kinesis/__init__.py
ADD localstack/constants.py localstack/config.py localstack/
ADD localstack/services/install.py localstack/services/
ADD localstack/utils/common.py localstack/utils/bootstrap.py localstack/utils/
ADD localstack/utils/aws/ localstack/utils/aws/
ADD localstack/utils/kinesis/ localstack/utils/kinesis/

# install dependencies
RUN make install

# add files required to run "make init"
ADD localstack/package.json localstack/package.json
ADD localstack/services/__init__.py localstack/services/install.py localstack/services/

# initialize installation (downloads remaining dependencies)
RUN make init

# (re-)install web dashboard dependencies (already installed in base image)
ADD localstack/dashboard/web localstack/dashboard/web
RUN make install-web

# install supervisor config file and entrypoint script
ADD bin/supervisord.conf /etc/supervisord.conf
ADD bin/docker-entrypoint.sh /usr/local/bin/

# expose service & web dashboard ports (including edge)
EXPOSE 4566-4597 8080

# define command at startup
ENTRYPOINT ["docker-entrypoint.sh"]

# expose default environment (required for aws-cli to work)
ENV MAVEN_CONFIG=/opt/code/localstack \
    USER=localstack \
    PYTHONUNBUFFERED=1

# clean up and prepare for squashing the image
RUN apk del --purge git
RUN pip uninstall -y awscli boto3 botocore localstack_client idna s3transfer
RUN rm -rf /tmp/*.zip /tmp/*.jar /tmp/*.tar.gz /tmp/*.tgz /root/.cache /opt/yarn-v1.15.2
RUN ln -s /opt/code/localstack/.venv/bin/aws /usr/bin/aws
ENV PYTHONPATH=/opt/code/localstack/.venv/lib/python3.8/site-packages

# add rest of the code
ADD localstack/ localstack/
ADD bin/localstack bin/localstack

# fix some permissions and create local user
RUN ES_BASE_DIR=localstack/infra/elasticsearch; \
    mkdir -p /.npm && \
    mkdir -p $ES_BASE_DIR/data && \
    mkdir -p $ES_BASE_DIR/logs && \
    chmod 777 . && \
    chmod 755 /root && \
    chmod -R 777 /.npm && \
    chmod -R 777 $ES_BASE_DIR/config && \
    chmod -R 777 $ES_BASE_DIR/data && \
    chmod -R 777 $ES_BASE_DIR/logs && \
    chmod -R 777 /tmp/localstack && \
    adduser -D localstack && \
    chown -R localstack:localstack . /tmp/localstack && \
    ln -s `pwd` /tmp/localstack_install_dir

# run tests (to verify the build before pushing the image)
ADD tests/ tests/
RUN LAMBDA_EXECUTOR=local make test
