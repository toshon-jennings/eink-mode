CC = swiftc
CFLAGS = -O -parse-as-library
TARGET = bin/eink
SOURCES = src/main.swift

.PHONY: all clean asset install

all: $(TARGET) asset

$(TARGET): $(SOURCES)
	@mkdir -p bin
	$(CC) $(SOURCES) -o $(TARGET)
	@echo "Built $(TARGET)"

asset: assets/eink_paper.png assets/eink_dark_paper.png assets/og_image.png

assets/eink_paper.png assets/eink_dark_paper.png: src/generate_paper.swift
	@mkdir -p assets
	swift src/generate_paper.swift

assets/og_image.png: src/generate_og_image.swift
	@mkdir -p assets
	swift src/generate_og_image.swift assets/og_image.png

clean:
	rm -rf $(TARGET) dist

dist: $(TARGET) asset
	@mkdir -p dist/eink-v0.1.0/assets
	swiftc -O -target arm64-apple-macos13.0 src/main.swift -o dist/eink-arm64
	swiftc -O -target x86_64-apple-macos13.0 src/main.swift -o dist/eink-x86_64
	lipo -create dist/eink-arm64 dist/eink-x86_64 -output dist/eink-v0.1.0/eink
	@rm -f dist/eink-arm64 dist/eink-x86_64
	cp assets/eink_paper.png assets/eink_dark_paper.png dist/eink-v0.1.0/assets/
	cp README.md dist/eink-v0.1.0/
	tar -czvf dist/eink-v0.1.0-macos.tar.gz -C dist eink-v0.1.0
	shasum -a 256 dist/eink-v0.1.0-macos.tar.gz > dist/eink-v0.1.0-macos.tar.gz.sha256
	@echo "Built dist/eink-v0.1.0-macos.tar.gz"

install: $(TARGET)
	@echo "To make 'eink' available system-wide in your terminal, add to your ~/.zshrc:"
	@echo '  export PATH="$$HOME/eink-mode/bin:$$PATH"'
