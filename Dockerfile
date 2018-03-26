from buildpack-deps:trusty

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y; apt-get upgrade -y; apt-get dist-upgrade -y

RUN apt-get install --upgrade -y \
      apt-utils \
      autojump \
      bash \
      build-essential \
      cmake \
      curl \
      git \
      inetutils-ping \
      net-tools \
      openssh-server \
      sudo \
      vim \
      tcpdump

RUN apt-get update && apt-get install -y \
   libgeos-c1 \
   libprotobuf-dev \
   libtokyocabinet-dev \
   libpq-dev \
   protobuf-compiler \
   python-dev

#####################################################################
# Setup ssh service
RUN mkdir /var/run/sshd
RUN echo 'root:pylayers' | chpasswd
RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile
#####################################################################

# Add Tini. Tini operates as a process subreaper for jupyter. This prevents
# kernel crashes.
ENV TINI_VERSION v0.6.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini
ENTRYPOINT ["/usr/bin/tini", "--"]

# Configure environment
ENV CONDA_DIR=/opt/conda \
        SHELL=/bin/bash \
        NB_USER=pylayers \
        NB_UID=1000 \
        NB_GID=100 \
        LC_ALL=en_US.UTF-8 \
        LANG=en_US.UTF-8 \
        LANGUAGE=en_US.UTF-8

ENV PATH=$CONDA_DIR/bin:$PATH \
              HOME=/home/$NB_USER

ADD fix-permissions /usr/local/bin/fix-permissions

# Create jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd /etc/group && \
    fix-permissions $HOME &&\
    fix-permissions $CONDA_DIR

USER $NB_UID

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

ENV CONDA_VER 4.3.1

RUN cd /tmp && \
    wget --quiet https://repo.continuum.io/archive/Anaconda2-${CONDA_VER}-Linux-x86_64.sh && \
    /bin/bash Anaconda2-${CONDA_VER}-Linux-x86_64.sh -f -b -p $CONDA_DIR && \
    rm Anaconda2-${CONDA_VER}-Linux-x86_64.sh && \
    $CONDA_DIR/bin/conda config --system --prepend channels conda-forge && \
    $CONDA_DIR/bin/conda config --system --set auto_update_conda false && \
    $CONDA_DIR/bin/conda config --system --set show_channel_urls true && \
    $CONDA_DIR/bin/conda update --all --quiet --yes && \
    conda clean -tipsy && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

WORKDIR $HOME/work

RUN git clone https://github.com/pylayers/pylayers
RUN cd pylayers && chmod a+x ./installer_unix && \
    ./installer_unix
RUN pip install simpy shapely imposm
RUN conda upgrade notebook

ADD plot_exDLink.ipynb  /home/$NB_USER/work

USER root

EXPOSE 8888
WORKDIR $HOME

# Configure container startup
CMD ["start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-notebook.sh /usr/local/bin/
COPY start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/
RUN fix-permissions /etc/jupyter/

# Switch back to pylayers to avoid accidental container runs as root
USER $NB_UID
