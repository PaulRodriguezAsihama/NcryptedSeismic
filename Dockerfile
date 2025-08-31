FROM continuumio/miniconda3:latest

# Actualizar conda y pip
RUN conda update -n base -c defaults conda && \
    pip install --upgrade pip

# Instalar dependencias del sistema para segyio
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Crear ambiente conda con Python 3.9
RUN conda create -n seismic python=3.9 -y

# Activar ambiente e instalar paquetes
SHELL ["conda", "run", "-n", "seismic", "/bin/bash", "-c"]

# Instalar paquetes científicos y geofísicos
RUN conda install -c conda-forge \
    numpy \
    scipy \
    matplotlib \
    jupyter \
    ipython \
    -y

# Instalar segyio y otras herramientas via pip
RUN pip install \
    segyio \
    tqdm \
    h5py \
    pandas \
    scikit-learn

# Directorio de trabajo
WORKDIR /workspace

# Activar el ambiente por defecto
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "seismic"]
CMD ["/bin/bash"]
