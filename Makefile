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
	rm -f $(TARGET)

install: $(TARGET)
	@echo "To make 'eink' available system-wide in your terminal, add to your ~/.zshrc:"
	@echo '  export PATH="$$HOME/eink-mode/bin:$$PATH"'
