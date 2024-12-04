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

# Configura el proveedor Docker para que Terraform interactúe con Docker en mi máquina local.
provider "docker" {}

# Crear la red Docker para que los contenedores se comuniquen.
resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

# Crear el contenedor Docker in Docker (DinD).
resource "docker_container" "jenkins_dind" {
  image       = "docker:dind"
  name        = "jenkins-dind"
  privileged  = true
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["dind"]
  }
  env = [
    # Habilitamos TLS para seguridad.
    "DOCKER_TLS_CERTDIR=/certs"
  ]
  mounts {
    # Montamos un volumen para almacenar los certificados TLS generados por DinD.
    source = "jenkins-dind-certs"
    target = "/certs"
    type   = "volume"
  }
  ports {
    # El puerto 2376 es el puerto estándar utilizado por Docker para habilitar comunicación segura mediante TLS.
    internal = 2376
    external = 2376
  }
}

# Crear el contenedor de Jenkins.
resource "docker_container" "jenkins" {
  image       = "myjenkins-blueocean"
  name        = "jenkins-blueocean"
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["jenkins"]
  }
  env = [
    # Define la dirección del servidor Docker con el que Jenkins se conectará.
    "DOCKER_HOST=tcp://dind:2376",
    # Especifica la ruta en el contenedor donde están almacenados los certificados TLS necesarios para la autenticación segura.
    "DOCKER_CERT_PATH=/certs/client",
    # Habilita la verificación TLS para asegurar que la comunicación entre Jenkins y jenkins-dind sea cifrada y autenticada.
    "DOCKER_TLS_VERIFY=1"
  ]
  mounts {
    # Compartimos los certificados generados por DinD con el contenedor Jenkins.
    source = "jenkins-dind-certs"
    target = "/certs"
    type   = "volume"
  }
  ports {
    # Permite acceder a la interfaz de Jenkins desde el navegador.
    internal = 8080
    external = 8080
  }
  ports {
    # Permite que agentes de Jenkins se conecten al servidor Jenkins.
    internal = 50000
    external = 50000
  }
}

# Crear el volumen compartido para los certificados.
resource "docker_volume" "jenkins_dind_certs" {
  name = "jenkins-dind-certs"
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
    # Configura el agente Docker para ejecutar el pipeline en un contenedor con Python preinstalado.
    agent {
        docker {
            image 'python:3.9' # Utiliza la imagen oficial de Python versión 3.9
        }
    }
    options {
        # Si las pruebas fallan o un archivo no es válido, las etapas posteriores no se ejecutarán.
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            steps {
                # Compila los archivos Python (add2vals.py y calc.py) para asegurarse de que no tienen errores de sintaxis.
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                # Guarda los archivos compilados para usarlos en etapas posteriores sin necesidad de recompilar.
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            steps {
                # Ejecuta pruebas automatizadas de un archivo de pruebas y genera un reporte.
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    # Publica los resultados de las pruebas en la interfaz.
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            steps {
                # Genera un ejecutable independiente a partir de un script asegurándose de que todo esté en un solo archivo ejecutable.
                sh "pyinstaller --onefile sources/add2vals.py" 
            }
            post {
                success {
                    # Si hay éxito, se archiva el ejecutable como un artefacto de Jenkins para permitir que pueda ser descargado desde Jenkins.
                    archiveArtifacts 'dist/add2vals' 
                }
            }
        }
    }
}

````
