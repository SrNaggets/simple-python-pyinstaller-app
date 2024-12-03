# Instrucciones

## 1) Instalar Docker, Git y Terraform

Verificar ````docker --version```` , ````git --version```` y ````terraform --version````


## 2) Creación imagen de Jenkins usando Dockerfile

````
 FROM jenkins/jenkins:2.479.2-jdk17
 USER root
 RUN apt-get update && apt-get install -y lsb-release
 RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
 https://download.docker.com/linux/debian/gpg
 RUN echo "deb [arch=$(dpkg --print-architecture) \
 signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
 https://download.docker.com/linux/debian \
 $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
 RUN apt-get update && apt-get install -y docker-ce-cli
 USER jenkins
 RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api"
````

## 3) Clonar repositorio

````git clone https://github.com/SrNaggets/simple-python-pyinstaller-app````

## 4) Construir la imagen en la carpeta simple-python-pyinstaller-app/docs

````docker build -t myjenkins-blueocean````   
Para verificar ````docker images````

## 5) Crear el despliegue en Terraform

Crear el archivo Despliegues.tf con el siguiente contenido:
````
# La configuración básica de Terraform.
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

# Configura el proveedor Docker para que Terraform interactue con Docker en mi máquina local
provider "docker" {}

# Crear la red Docker para que los contenedores se comuniquen
resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

# Crear el contenedor Docker in Docker (DinD)
resource "docker_container" "jenkins_dind" {
  image       = "docker:dind"
  name        = "jenkins-dind"
  privileged  = true
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["dind"]
  }
  env = {
    # Habilitamos TLS para seguridad
    DOCKER_TLS_CERTDIR = "/certs"
  }
  ports {
    # El puerto 2376 es el puerto estándar utilizado por Docker para habilitar comunicación segura mediante TLS 
    internal = 2376
    external = 2376
  }
}

# Crear el contenedor de Jenkins
resource "docker_container" "jenkins" {
  image       = "myjenkins-blueocean"
  name        = "jenkins-blueocean"
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["jenkins"]
  }
  env = {
    # Define la dirección del servidor Docker con el que Jenkins se conectará.
    DOCKER_HOST       = "tcp://dind:2376"
    # Especifica la ruta en el contenedor donde están almacenados los certificados TLS necesarios para la autenticación segura.
    DOCKER_CERT_PATH  = "/certs/client"
    # Habilita la verificación TLS para asegurar que la comunicación entre Jenkins y jenkins-dind sea cifrada y autenticada.
    DOCKER_TLS_VERIFY = "1"
  }
  ports {
    # Permite acceder a la interfaz de Jenkins desde el navegador
    internal = 8080
    external = 8080
  }
  ports {
    # Permite que agentes de Jenkins se conecten al servidor Jenkins.
    internal = 50000
    external = 50000
  }
}

````

## 6) Subir el despliegue al repositorio  

- Para añadirlo ````git add docs/Despliegues.tf````  
- Para comprobarlo ````git status````
- Para poder hacer el commit debo identificarme ````git config --global user.name "Tu Nombre"```` y ````git config --global user.email "tuemail@example.com"````
- Para hacer el commit ````git commit -m "Añadido archivo Despliegues.tf con configuración de Terraform"````
- Para hacer el push ````git push origin master````

  
