extern "C" void loadfunctions();

extern "C" __attribute__((visibility("default"))) void KuchieOpenJDKInitialize() {
  loadfunctions();
}
