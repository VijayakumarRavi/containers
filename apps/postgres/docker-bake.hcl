target "docker-metadata-action" {}

variable "APP" {
  default = "postgres"
}

variable "VERSION" {
  default = "17"
}

variable "SUPERCRONIC_VERSION" {
  // renovate: datasource=github-releases depName=aptible/supercronic
  default = "v0.2.41"
}

variable "SOURCE" {
  default = "https://github.com/postgres/postgres"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    POSTGRES_VERSION = "${VERSION}"
    SUPERCRONIC_VERSION = "${SUPERCRONIC_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
