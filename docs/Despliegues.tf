terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}


resource "docker_network" "jenkins_network" {
  name = "jenkins-network"
}

resource "docker_volume" "jenkins_volume" {
  name = "jenkins-volume"
}

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
  privileged = true
  networks_advanced {
    name = docker_network.jenkins_network.name
    aliases = ["docker"]
  }
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
  volumes {
    volume_name    = docker_volume.certs_volume.name
    container_path = "/certs/client"
  }
  volumes {
    volume_name    = docker_volume.jenkins_volume.name
    container_path = "/var/jenkins_home"
  }
  ports {
    internal = 2376
    external = 2376
  }
}


resource "docker_container" "jenkins_container" {
  name  = "jenkins"
  image = "myjenkins-blueocean" 
  restart = "unless-stopped"
  depends_on = [docker_container.dind_container] 
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
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
  ports {
    internal = 8080
    external = 8080
  }
  ports {
    internal = 50000
    external = 50000
  }
}


