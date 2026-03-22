BUILD   = build
SRC     = src
SHADERS = shaders

CXX      = clang++
CXXFLAGS = -std=c++17 -O3 -Wall -Wextra -I metal-cpp -I metal-cpp-extensions -I .
LDFLAGS  = -framework Metal -framework MetalKit -framework AppKit \
           -framework Foundation -framework QuartzCore

SRCS    = $(SRC)/main.cpp $(SRC)/renderer.cpp
MM_SRCS = $(SRC)/input_handler.mm
OBJS    = $(patsubst $(SRC)/%.cpp, $(BUILD)/%.o, $(SRCS)) \
          $(patsubst $(SRC)/%.mm,  $(BUILD)/%.o, $(MM_SRCS))

METAL_SRCS = $(wildcard $(SHADERS)/*.metal)
METAL_AIRS = $(patsubst $(SHADERS)/%.metal, $(BUILD)/%.air, $(METAL_SRCS))

.PHONY: all clean run

all: $(BUILD) $(BUILD)/BlackHole $(BUILD)/Shaders.metallib

run: all
	./$(BUILD)/BlackHole

$(BUILD):
	mkdir -p $(BUILD)

# Compile each .metal shader to .air
$(BUILD)/%.air: $(SHADERS)/%.metal | $(BUILD)
	xcrun -sdk macosx metal -O3 -I . -c $< -o $@

# Link all .air files into a single .metallib
$(BUILD)/Shaders.metallib: $(METAL_AIRS)
	xcrun -sdk macosx metallib $^ -o $@

# Compile C++ sources
$(BUILD)/%.o: $(SRC)/%.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Compile Objective-C++ sources
$(BUILD)/%.o: $(SRC)/%.mm | $(BUILD)
	$(CXX) $(CXXFLAGS) -fobjc-arc -c $< -o $@

# Link final binary
$(BUILD)/BlackHole: $(OBJS)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $^ -o $@

clean:
	rm -rf $(BUILD)
