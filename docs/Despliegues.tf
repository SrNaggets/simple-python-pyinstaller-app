terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

resource "docker_volume" "jenkins_dind_certs" {
  name = "jenkins-dind-certs"
}

resource "docker_container" "jenkins_dind" {
  image       = "docker:20.10.24-dind"  # Versión específica de DinD
  name        = "dind-container"
  privileged  = true
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  env = [
    "DOCKER_TLS_CERTDIR=/certs",
    "DOCKER_TLS_SAN=dind"
  ]
  mounts {
    source = docker_volume.jenkins_dind_certs.name
    target = "/certs"
    type   = "volume"
  }
  ports {
    internal = 2376
    external = 2377
  }
}

resource "docker_container" "jenkins" {
  image       = "myjenkins-blueocean"  # Imagen personalizada de Jenkins
  name        = "jenkins-blueocean"
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  env = [
    "DOCKER_HOST=tcp://dind:2377",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]
  mounts {
    source = docker_volume.jenkins_dind_certs.name
    target = "/certs"
    type   = "volume"
  }
  ports {
    internal = 8080
    external = 8080
  }
  ports {
    internal = 50000
    external = 50000
  }
}
