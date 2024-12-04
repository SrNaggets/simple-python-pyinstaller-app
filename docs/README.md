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
# Define el proveedor y la versión
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}
# Configura proveedor Docker, que permitirá a Terraform interacturar con Docker para gestionar los contenedores, redes y volúmenes
provider "docker" {}

# Permite que los contenedores de Jenkins y Docker-in-Docker se comuniquen entre sí dentro de una red privada y aislada
resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

# Este volumen asegura que los datos de certificados TSL persistan incluso si el contenedor es eliminado.
resource "docker_volume" "jenkins_dind_certs" {
  name = "jenkins-dind-certs"
}

resource "docker_container" "jenkins_dind" {
  image       = "docker:20.10.24-dind"
  name        = "dind-container"
  # Para ejecutar Docker dentro de Docker es necesario que el contenedor tenga privilegios
  privileged  = true

  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  # El directorio donde se almacenan los certificados TLS para la comunicación segura entre Docker y Jenkins.
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
  # Monta el volumen para almacenar los certificados TLS.
  mounts {
    source = "jenkins-dind-certs"
    target = "/certs"
    type   = "volume"
  }
  # Monta un volumen para almacenar los datos del daemon de Docker 
  mounts {
    target = "/var/lib/docker"
    type   = "volume"
  }
  # Expone el puerto interno 2376 de Docker en el puerto externo 2377 para que Jenkins pueda conectarse al daemon de Docker.
  ports {
    internal = 2376
    external = 2377
  }
}


resource "docker_container" "jenkins" {
  # Uso de la imagen hecha con el Dockerfile
  image       = "myjenkins-blueocean"  
  name        = "jenkins-blueocean"
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  env = [
     # Configura Jenkins para que se conecte al daemon Docker del contenedor dind-container a través del puerto 2377
    "DOCKER_HOST=tcp://dind:2377",
     # Especifica la ruta donde Jenkins buscará los certificados TLS para conectarse de manera segura al daemon de Docker
    "DOCKER_CERT_PATH=/certs/client",
     # Habilita la verificación TLS
    "DOCKER_TLS_VERIFY=1"
  ]
  # Monta el volumen jenkins-dind-certs en /certs dentro del contenedor Jenkins para usar los certificados TLS compartidos.
  mounts {
    source = docker_volume.jenkins_dind_certs.name
    target = "/certs"
    type   = "volume"
  }
  # Interfaz web de Jenkins.
  ports {
    internal = 8080
    external = 8080
  }
  # Puerto usado para la comunicación con agentes de Jenkins
  ports {
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
- Para hacer el push ````git push````

## 7) Aplicar Terraform

- Editar el archivo .gitignore para que Git evite rastrear los archivos generados automáticamente por Terraform ya que contienen información sensible, como credenciales o detalles específicos del entorno, al final del archivo .gitignore incluir:
````
# Ignorar archivos de Terraform
.terraform/
.terraform.lock.hcl
terraform.tfstate
terraform.tfstate.backup
````
- Inicializar el directorio de trabajo con la configuración hecha ````terraform init````
- Verificar si la configuración es sintacticamente válida ````terraform validate````
- Aplicar los archivos de configuración ````terraform apply````

## 8) Crear Pipeline en Jenkins

- Accede a Jenkins en http://localhost:8080
- Usa la clave inicial que saldrá con ````docker exec -it jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword````
- Instalar plugins recomendados y crear usuario
- Crear nueva tarea tipo Pipeline
- Configuracion: Pipeline script from SCM, SCM git, url del fork, Script path = ubicación Jenkinsfile

## 9) Edición Jenkinsfile

````
pipeline {
    # Un contenedor Docker efímero para ejecutar las etapas definidas a continuación, se comunica con el dind container para ejecutar comandos Docker
    agent {
        docker {
            image 'docker:19.03.12' 
            # Da permisos adicionales para que pueda ejecutar comandos de Docker dentro de Docker y monta los certificados TSL compartidos para poder comunicarse de forma segura con el contenedor dind
            args '--privileged -v /certs:/certs -e DOCKER_TLS_CERTDIR=/certs'
        }
    }
    stages {
        stage('Build') {
            steps {
                # Compila los archivos Python para verificar que no contienen errores de sintaxis.
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
            }
        }
        stage('Test') {
            steps {
                # Ejecuta el archivo con las pruebas unitarias para validar que las funciones de los archivos Pyhton funcionan correctamente y genera el reporte en formato JUnit XML
                sh 'pytest --junit-xml test-reports/results.xml sources/test_calc.py'
            }
        }
        stage('Deploy') {
            steps {
                # Crea un ejecutable a partir del script Python que incluye todo lo necesario para ejecutarse sin depender de un intérprete Python.
                sh 'pyinstaller --onefile sources/add2vals.py'
            }
        }
    }
}

````
