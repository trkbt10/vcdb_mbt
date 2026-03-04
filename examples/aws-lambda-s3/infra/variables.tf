variable "region" {
  default = "ap-northeast-1"
}

variable "env" {
  default = "dev"
}

variable "package_path" {
  default = "../ts-native/function.zip"
}

variable "memory" {
  default = 512
}

variable "timeout" {
  default = 30
}
