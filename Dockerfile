FROM docker.io/maven:3-jdk-8-slim

MAINTAINER Waldemar Hummer (waldemar.hummer@gmail.com)
LABEL authors="Waldemar Hummer (waldemar.hummer@gmail.com), Gianluca Bortoli (giallogiallo93@gmail.com)"

RUN apt-get update

# install supervisor
RUN apt-get install -y supervisor


# install python
RUN apt-get install -y build-essential python python-dev curl wget
RUN curl -sL curl -sL https://bootstrap.pypa.io/get-pip.py | python -
RUN pip install virtualenv

# install node
RUN curl -sL curl -sL https://deb.nodesource.com/setup_8.x | bash -
RUN apt-get install -y nodejs

# set workdir
RUN mkdir -p /opt/code/localstack
WORKDIR /opt/code/localstack/

# init environment and cache some dependencies
ADD requirements.txt .
RUN mkdir -p /opt/code/localstack/localstack/infra && \
    wget -O /tmp/localstack.es.zip \
        https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.2.0.zip && \
    wget -O /tmp/elasticmq-server.jar \
        https://s3-eu-west-1.amazonaws.com/softwaremill-public/elasticmq-server-0.14.5.jar && \
    (cd localstack/infra/ && unzip -q /tmp/localstack.es.zip && \
        mv elasticsearch* elasticsearch && rm /tmp/localstack.es.zip) && \
    mkdir -p /opt/code/localstack/localstack/infra/dynamodb && \
    wget -O /tmp/localstack.ddb.zip \
        https://s3-us-west-2.amazonaws.com/dynamodb-local/dynamodb_local_latest.zip && \
    (cd localstack/infra/dynamodb && unzip -q /tmp/localstack.ddb.zip && rm /tmp/localstack.ddb.zip)
RUN (pip install --upgrade pip) && \
    (test `which virtualenv` || pip install virtualenv || sudo pip install virtualenv) && \
    (virtualenv .testvenv && . .testvenv/bin/activate && \
        pip install -q six==1.10.0 && pip install -q -r requirements.txt && \
        rm -rf .testvenv)

# add files required to run "make install"
ADD Makefile requirements.txt ./
RUN mkdir -p localstack/utils/kinesis/ && mkdir -p localstack/services/ && \
  touch localstack/__init__.py localstack/utils/__init__.py localstack/services/__init__.py localstack/utils/kinesis/__init__.py
ADD localstack/constants.py localstack/config.py localstack/
ADD localstack/services/install.py localstack/services/
ADD localstack/utils/common.py localstack/utils/
ADD localstack/utils/kinesis/ localstack/utils/kinesis/
ADD localstack/ext/ localstack/ext/

# install dependencies
RUN make install

# add files required to run "make init"
ADD localstack/package.json localstack/package.json
ADD localstack/services/__init__.py localstack/services/install.py localstack/services/

# initialize installation (downloads remaining dependencies)
RUN make init

# add rest of the code
ADD localstack/ localstack/
ADD bin/localstack bin/localstack

# (re-)install web dashboard dependencies (already installed in base image)
RUN make install-web

# fix some permissions and create local user
RUN mkdir -p /.npm && \
    mkdir -p localstack/infra/elasticsearch/data && \
    mkdir -p localstack/infra/elasticsearch/logs && \
    chmod 777 . && \
    chmod 755 /root && \
    chmod -R 777 /.npm && \
    chmod -R 777 localstack/infra/elasticsearch/config && \
    chmod -R 777 localstack/infra/elasticsearch/data && \
    chmod -R 777 localstack/infra/elasticsearch/logs && \
    chmod -R 777 /tmp/localstack && \
    chown -R `id -un`:`id -gn` . && \
    adduser --disabled-password --gecos "" localstack && \
    ln -s `pwd` /tmp/localstack_install_dir

# expose default environment (required for aws-cli to work)
ENV MAVEN_CONFIG=/opt/code/localstack \
    USER=localstack \
    PYTHONUNBUFFERED=1

# expose service & web dashboard ports
EXPOSE 4567-4583 8080

# install supervisor daemon & copy config file
ADD bin/supervisord.conf /etc/supervisord.conf

# define command at startup
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

# run tests (to verify the build before pushing the image)
ADD tests/ tests/
RUN make test
