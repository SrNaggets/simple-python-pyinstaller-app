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

Para construir la imagen, en el directorio donde se encuentra el Dockerfile ````docker build -t myjenkins-blueocean .````(el punto del final incluido para indicar directorio actual)   
Para verificar ````docker images````

## 5) Crear el despliegue en Terraform

Crear el archivo Despliegues.tf con el siguiente contenido:
````
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}
# Define cómo se conecta Terraform al servicio Docker.

provider "docker" {}

# Jenkins necesita comunicarse con DinD para enviarle comandos Docker.

resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

# El volumen para Jenkins es esencial para almacenar de manera persistente la configuración del servidor, los plugins, el historial de builds, los artefactos generados y las definiciones de pipelines. Esto asegura que, aunque el contenedor de Jenkins sea detenido o eliminado, toda esta información no se pierda, permitiendo reiniciar o migrar Jenkins sin necesidad de volver a configurarlo desde cero. También facilita la realización de backups y la restauración de datos en caso de fallos.

resource "docker_volume" "jenkins_volume" {
  name = "jenkins_volume"
}

# El volumen para DinD almacena de forma persistente las imágenes Docker, los contenedores creados durante los pipelines y los datos operativos del demonio Docker. Esto evita que se pierdan imágenes o contenedores al reiniciar DinD, ahorrando tiempo al no tener que reconstruirlos. Además, asegura un mejor rendimiento y permite gestionar eficientemente el almacenamiento, especialmente cuando se trabaja con múltiples builds o pruebas en el pipeline.

resource "docker_volume" "dind_volume" {
  name = "dind_volume"
}


resource "docker_container" "dind_container" {
  image       = "docker:20.10.24-dind"
  name        = "dind_container"

# Para ejecutar Docker dentro de Docker es necesario que el contenedor tenga privilegios

  privileged  = true

  networks_advanced {
    name    = docker_network.jenkins_network.name

# Jenkins se comunicará con Dind para enviarle los comandos Docker, por tanto necesita saber como acceder al contenedor, así es mas claro

    aliases = ["dind"]
  }

  volumes {
    volume_name   = docker_volume.dind_volume.name
    container_path = "/var/lib/docker"
  }

  ports {

# 2375 es el puerto predeterminado para comunicaciones no seguras donde el demonio Docker escucha las conexiones.

    internal = 2375
    external = 2375
  }
}

resource "docker_container" "jenkins_container" {
  image       = "myjenkins-blueocean"  
  name        = "jenkins_container"

# Como Dind no se comunica con Jenkins pues es Jenkins quien envia los comandos a Dind, no es útil usar un alias 

  networks_advanced {
    name = docker_network.jenkins_network.name
  }

  volumes {
    volume_name   = docker_volume.jenkins_volume.name
    container_path = "/var/jenkins_home"
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
- Inicializar el directorio de trabajo con la configuración hecha, instalando el proveedor de docker ````terraform init````
- Verificar si la configuración es sintacticamente válida ````terraform validate````
- Aplicar los archivos de configuración ````terraform apply````

## 8) Crear Pipeline en Jenkins

- Accede a Jenkins en http://localhost:8080
- Usa la clave inicial que saldrá con ````docker exec -it jenkins_container cat /var/jenkins_home/secrets/initialAdminPassword````
- Instalar plugins recomendados y crear usuario
- Crear nueva tarea tipo Pipeline
- Configuracion: Pipeline script from SCM, SCM git, url del fork, Script path = ubicación Jenkinsfile

## 9) Edición Jenkinsfile

````
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.0-alpine3.18'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            agent any
            environment { 
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) { 
                    unstash(name: 'compiled-results') 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'" 
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
 }




````
