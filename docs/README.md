# Instrucciones

## 1) Instalar Docker, Git y Terraform

Verificar ````docker --version```` , ````git --version```` y ````terraform --version````


## 2) Creación imagen de Jenkins usando Dockerfile

````
# Usa una imagen de Jenkins con la JDK con la capacidad de interactuar con Docker y instala plugins esenciales para pipelines modernos y manejo de contenedores
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
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}
# Docker Desktop me configura automáticamente el socket necesario, eliminando la necesidad de configurar manualmente el host.
provider "docker" {}

# La misma red para ambos contenedores para que se puedan comunicar
resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

# Para que configuraciones, credenciales, logs y el estado de los pipelines, no se pierda al reiniciar o actualizar el contenedor.
resource "docker_volume" "jenkins_volume" {
  name = "jenkins-volume"
}

# Para almacenar los certificados necesarios TLS para comunicación segura.
resource "docker_volume" "certs_volume" {
  name = "certs"
}

resource "docker_image" "dind_image" {
  name         = "docker:dind"
  keep_locally = false
}


resource "docker_container" "dind_container" {
  name  = "dind"
  image = docker_image.dind_image.name

# Necesita permisos para ejecutar los comandos de Docker
  privileged = true

  networks_advanced {
    name = docker_network.jenkins_network.name

# Para no depender de la dirección IP uso el alias, uso "Docker" pues no todos los alias son reconocidos como válidos.
    aliases = ["docker"]

  }

# Para habilitar TLS
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  volumes {
    volume_name    = docker_volume.certs_volume.name
    container_path = "/certs/client"
  }

# El contenedor de Dind usa el volumen de los datos compartidos por Jenkins pues puede necesitarlos para construir o ejecutar contenedores.
  volumes {
    volume_name    = docker_volume.jenkins_volume.name
    container_path = "/var/jenkins_home"
  }

# Puerto de Docker para conexiones seguras
  ports {
    internal = 2376
    external = 2376
  }
}


resource "docker_container" "jenkins_container" {
  name  = "jenkins"
  image = "myjenkins-blueocean"

# Para que se reinicie siempre a no ser que lo pause manualmente, 
  restart = "unless-stopped"

# El contenedor de Dind es conveniente que esté listo antes que el de Jenkins pues este accederá a Dind
  depends_on = [docker_container.dind_container] 

  networks_advanced {
    name = docker_network.jenkins_network.name
  }

# Para conectarse a Dind y habilitar la verificación de certificados y su ubicación
  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]
  volumes {
    volume_name    = docker_volume.jenkins_volume.name
    container_path = "/var/jenkins_home"
  }
  volumes {
    volume_name    = docker_volume.certs_volume.name
    container_path = "/certs/client"
    read_only      = true
  }

# Puertos de la interfaz de Jenkins
  ports {
    internal = 8080
    external = 8080
  }

# Para agentes remotos de Jenkins
  ports {
    internal = 50000
    external = 50000
  }
}



````

## 6) Subir el despliegue al repositorio  

- Para añadirlo ````git add docs/Despliegues.tf````  
- Para comprobarlo ````git status````
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
    # No se asignará un agente global, cada etapa especificará su agente
    agent none
    options {
        # Si una etapa falla, las siguientes etapas serán omitidas
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                # Utiliza un contenedor Docker con Python en Alpine Linux
                docker {
                    image 'python:3.12.0-alpine3.18'
                }
            }
            steps {
                # Compila los archivos Python para verificar errores de sintaxis y los guarda para usarlos en etapas posteriores.
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                # Utiliza un contenedor Docker con pytest para ejecutar pruebas.
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                # Ejecuta las pruebas unitarias y genera un reporte en formato XML.
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    # Publica siempre el resultado de las pruebas aunque fallen.
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            # Esta etapa puede ejecutarse en cualquier agente
            agent any
            environment { 
                VOLUME = '$(pwd)/sources:/src'
                # Usa una imagen Docker específica para empaquetar el artefacto
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) { 
                    # Recupera los resultados compilados de la etapa Build
                    unstash(name: 'compiled-results') 
                    # Usa PyInstaller dentro de un contenedor para generar un ejecutable de Python.
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'" 
                }
            }
            post {
                success {
                    # Guarda el artefacto generado como parte de los resultados de Jenkins
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
 }




````
