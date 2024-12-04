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
  name = "jenkins"
}

resource "docker_container" "jenkins_dind" {
  image       = "docker:dind"
  name        = "jenkins-dind"
  privileged  = true
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["dind"]
  }
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
  mounts {
    source = "jenkins-dind-certs"
    target = "/certs"
    type   = "volume"
  }
  ports {
    internal = 2376
    external = 2376
  }
}

resource "docker_container" "jenkins" {
  image       = "myjenkins-blueocean"
  name        = "jenkins-blueocean"
  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["jenkins"]
  }
  env = [
    "DOCKER_HOST=tcp://dind:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]
  mounts {
    source = "jenkins-dind-certs"
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

resource "docker_volume" "jenkins_dind_certs" {
  name = "jenkins-dind-certs"
}


