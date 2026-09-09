// Web platformu için dart:io stub'ı
// File sınıfının web'de kullanılmadığı durumlarda derleme hatası önler
class File {
  File(String path);
  Future<bool> exists() async => false;
  Future<File> delete() async => this;
}
