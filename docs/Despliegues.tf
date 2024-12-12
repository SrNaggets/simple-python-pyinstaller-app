terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}


resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}

resource "docker_volume" "jenkins_certs" {
  name = "jenkins-docker-certs"
}


resource "docker_image" "dind_image" {
  name         = "docker:dind"
  keep_locally = false
}


resource "docker_container" "dind" {
  name  = "jenkins-docker"
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
    volume_name    = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }
  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
  ports {
    internal = 2376
    external = 2376
  }
}


resource "docker_container" "jenkins" {
  name  = "jenkins-blueocean"
  image = "myjenkins-blueocean" 
  restart = "on-failure"
  depends_on = [docker_container.dind] 
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]
  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
  volumes {
    volume_name    = docker_volume.jenkins_certs.name
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


