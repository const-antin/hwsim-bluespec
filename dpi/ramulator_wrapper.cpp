// ramulator2-rs/ramulator_wrapper.cpp
#include "ramulator_wrapper.h"

// C++ standard library includes
#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>

// Disable spdlog completely before any includes
#define SPDLOG_DISABLE
#include <spdlog/spdlog.h>
#undef SPDLOG_DISABLE

// Global flag to track if spdlog has been initialized
static bool spdlog_initialized = false;

// Global flag to track if ramulator library has been initialized
static bool ramulator_initialized = false;

// Function to safely initialize spdlog only once
void initialize_spdlog_safely() {
    if (!spdlog_initialized) {
        try {
            // Completely disable spdlog
            spdlog::set_level(spdlog::level::off);
            spdlog::flush_on(spdlog::level::off);
            
            // Try to get existing logger first
            auto existing_logger = spdlog::get("Ramulator::Base");
            if (!existing_logger) {
                // Create a simple logger that does nothing
                auto logger = spdlog::stdout_color_mt("Ramulator::Base");
                if (logger) {
                    logger->set_level(spdlog::level::off);
                }
            }
            spdlog_initialized = true;
        } catch (const spdlog::spdlog_ex& e) {
            // Logger already exists, ignore the error
            spdlog_initialized = true;
        } catch (...) {
            // Any other error, just mark as initialized
            spdlog_initialized = true;
        }
    }
}

// Function to safely initialize ramulator library only once
void initialize_ramulator_safely() {
    if (!ramulator_initialized) {
        try {
            // Any global ramulator initialization can go here
            ramulator_initialized = true;
        } catch (...) {
            // Any error, just mark as initialized
            ramulator_initialized = true;
        }
    }
}

RamulatorWrapper::RamulatorWrapper(const char *config_path)
    : config_path(config_path) {
  if (!config_path) {
    throw std::invalid_argument("Invalid argument");
  }

  // Initialize spdlog safely before any ramulator operations
  initialize_spdlog_safely();
  
  // Initialize ramulator library safely
  initialize_ramulator_safely();

  std::cout << "Loading config file: " << config_path << std::endl;

  // Parse configuration
  auto config = Ramulator::Config::parse_config_file(config_path, {});
  // auto test = Ramulator::Config::parse_content(config_path, {});

  // Create frontend with the configuration
  // frontend = std::make_unique<Ramulator::Frontend>(*(config));
  frontend = Ramulator::Factory::create_frontend(config);
  memory_system = Ramulator::Factory::create_memory_system(config);

  frontend->connect_memory_system(memory_system);
  memory_system->connect_frontend(frontend);

  initialized = true;
}

RamulatorWrapper::~RamulatorWrapper() {
  if (initialized) {
    frontend->finalize();
    memory_system->finalize();
  }
}

bool RamulatorWrapper::send_request(uint64_t addr, bool is_write) {
  if (!initialized) {
    throw std::runtime_error("Ramulator instance not initialized");
  }

  std::lock_guard<std::mutex> lock(frontend_mutex);

  bool enqueue_success = false;

  if (is_write) {
    enqueue_success = frontend->receive_external_requests(
        1, addr, 0, [this](Ramulator::Request &req) {
          this->out_queue.push(req.addr);
          // int chan_id = req.addr_vec[0];
          std::atomic_fetch_sub(&num_outstanding_writes, 1);
        });

    if (enqueue_success) {
      // std::cout << "Request enqueued successfully" << std::endl;
      // auto &packet = outstandingReads.find(addr)->second;
      std::atomic_fetch_add(&num_outstanding_writes, 1);
    } else {
      // std::cout << "Request enqueue failed (queue full)" << std::endl;
    }
  } else {
    enqueue_success = frontend->receive_external_requests(
        0, addr, 0, [this](Ramulator::Request &req) {
          this->out_queue.push(req.addr);
          std::atomic_fetch_sub(&num_outstanding_reads, 1);
        });
    if (enqueue_success) {
      // std::cout << "Request enqueued successfully" << std::endl;
      // auto &packet = outstandingReads.find(addr)->second;
      std::atomic_fetch_add(&num_outstanding_reads, 1);
    } else {
      // std::cout << "Request enqueue failed (queue full)" << std::endl;
    }
  }

  return enqueue_success;
}

void RamulatorWrapper::tick() {
  std::atomic_fetch_add(&tCK, 1);
  frontend->tick();
  memory_system->tick();
}

bool RamulatorWrapper::is_finished() {
  return frontend->is_finished();
  // return num_outstanding_reads == 0 && num_outstanding_writes == 0 && frontend->is_finished();
  // return outgoing_reqs == 0 && frontend->is_finished();
}

void *ramulator_new(const char *config_path) {
  auto sim = new RamulatorWrapper(config_path);
  return sim;
}

void ramulator_free(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (sim_wrapper) {
    delete sim_wrapper;
  }
}

bool ramulator_send_request(void *sim, uint64_t addr, bool is_write) {
  if (!sim) {
    std::cerr << "Simulator instance is null" << std::endl;
    return false;
  }
  auto sim_wrapper = (RamulatorWrapper *)sim;
  return sim_wrapper->send_request(addr, is_write);
}

void ramulator_tick(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (!sim_wrapper) {
    std::cerr << "Error: Simulator instance is null" << std::endl;
    return;
  }
  sim_wrapper->tick();
}

uint64_t ramulator_pop(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (!sim_wrapper) {
    std::cerr << "Error: Simulator instance is null" << std::endl;
    return 0;
  }
  return sim_wrapper->pop();
}

bool ramulator_is_finished(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (!sim_wrapper) {
    std::cerr << "Error: Simulator instance is null" << std::endl;
    return false; // Treat as not finished if invalid
  }

  return sim_wrapper->is_finished();
}

float ramulator_get_cycle(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (!sim_wrapper) {
    std::cerr << "Error: Simulator instance is null" << std::endl;
    return 0;
  }

  return sim_wrapper->get_cycle();
}

bool ramulator_ret_available(void *sim) {
  auto sim_wrapper = (RamulatorWrapper *)sim;
  if (!sim_wrapper) {
    std::cerr << "Error: Simulator instance is null" << std::endl;
    return false;
  }

  return sim_wrapper->return_available();
}

// Global simulator instance for BDPI functions
static RamulatorWrapper* global_sim = nullptr;
static const char* default_config_path = "./ramulator2/example_config_bh.yaml";

// BDPI functions for Bluespec interface
void ramulator_wrapper_init(void) {
  if (global_sim == nullptr) {
    try {
      global_sim = new RamulatorWrapper(default_config_path);
      std::cout << "Ramulator wrapper initialized successfully" << std::endl;
    } catch (const std::exception& e) {
      std::cerr << "Failed to initialize ramulator wrapper: " << e.what() << std::endl;
    }
  }
}

void ramulator_wrapper_free(void) {
  if (global_sim != nullptr) {
    delete global_sim;
    global_sim = nullptr;
    std::cout << "Ramulator wrapper freed" << std::endl;
  }
}

void ramulator_wrapper_send(uint64_t addr, bool is_write) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return;
  }
  
  bool success = global_sim->send_request(addr, is_write);
  if (!success) {
    std::cerr << "Warning: Failed to send request to ramulator" << std::endl;
  }
}

void ramulator_wrapper_tick(void) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return;
  }
  
  global_sim->tick();
}

void ramulator_wrapper_get_cycle(void) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return;
  }
  
  uint64_t cycle = global_sim->get_cycle();
  // Note: In a real implementation, you might want to return this value
  // For now, we just print it
  std::cout << "Current cycle: " << cycle << std::endl;
}

void ramulator_wrapper_ret_available(void) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return;
  }
  
  bool available = global_sim->return_available();
  // Note: In a real implementation, you might want to return this value
  // For now, we just print it
  std::cout << "Return available: " << (available ? "true" : "false") << std::endl;
}

uint64_t ramulator_wrapper_pop(void) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return 0;
  }
  
  if (!global_sim->return_available()) {
    std::cerr << "Warning: No return value available" << std::endl;
    return 0;
  }
  
  return global_sim->pop();
}

bool ramulator_wrapper_is_finished(void) {
  if (global_sim == nullptr) {
    std::cerr << "Error: Ramulator wrapper not initialized" << std::endl;
    return true; // Treat as finished if not initialized
  }
  
  return global_sim->is_finished();
}

// Pre-initialized memory storage
static std::unordered_map<uint64_t, uint8_t> pre_initialized_memory;
static uint64_t memory_start_addr = 0;
static uint64_t memory_size = 0;

// Pre-initialized memory functions
void ramulator_wrapper_init_memory(uint64_t start_addr, uint64_t size, const uint8_t* data) {
  memory_start_addr = start_addr;
  memory_size = size;
  pre_initialized_memory.clear();
  
  // Copy the data into our memory map
  for (uint64_t i = 0; i < size; i++) {
    pre_initialized_memory[start_addr + i] = data[i];
  }
  
  std::cout << "Pre-initialized memory: " << size << " bytes starting at 0x" 
            << std::hex << start_addr << std::dec << std::endl;
}

void ramulator_wrapper_read_memory(uint64_t addr, uint64_t size, uint8_t* buffer) {
  if (addr < memory_start_addr || addr + size > memory_start_addr + memory_size) {
    std::cerr << "Error: Memory access out of bounds" << std::endl;
    return;
  }
  
  for (uint64_t i = 0; i < size; i++) {
    auto it = pre_initialized_memory.find(addr + i);
    if (it != pre_initialized_memory.end()) {
      buffer[i] = it->second;
    } else {
      buffer[i] = 0; // Default to 0 for uninitialized memory
    }
  }
}

bool ramulator_wrapper_memory_available(uint64_t addr, uint64_t size) {
  return (addr >= memory_start_addr && addr + size <= memory_start_addr + memory_size);
}

// Sequential memory access state
static uint64_t sequential_start_addr = 0;
static uint64_t sequential_total_size = 0;
static uint64_t sequential_request_size = 64;
static uint64_t sequential_current_offset = 0;
static bool sequential_initialized = false;

// Sequential memory access functions
void ramulator_wrapper_init_sequential(uint64_t start_addr, uint64_t total_size, uint64_t request_size) {
  sequential_start_addr = start_addr;
  sequential_total_size = total_size;
  sequential_request_size = request_size;
  sequential_current_offset = 0;
  sequential_initialized = true;
  
  std::cout << "Sequential access initialized: " << total_size << " bytes starting at 0x" 
            << std::hex << start_addr << " with " << request_size << " byte requests" << std::dec << std::endl;
}

uint64_t ramulator_wrapper_get_next_sequential(void) {
  if (!sequential_initialized) {
    std::cerr << "Error: Sequential access not initialized" << std::endl;
    return 0;
  }
  
  if (sequential_current_offset >= sequential_total_size) {
    std::cerr << "Warning: No more sequential addresses available" << std::endl;
    return 0;
  }
  
  uint64_t current_addr = sequential_start_addr + sequential_current_offset;
  sequential_current_offset += sequential_request_size;
  
  return current_addr;
}

bool ramulator_wrapper_sequential_available(void) {
  if (!sequential_initialized) {
    return false;
  }
  
  return sequential_current_offset < sequential_total_size;
}

void ramulator_wrapper_reset_sequential(uint64_t new_start_addr) {
  sequential_start_addr = new_start_addr;
  sequential_current_offset = 0;
  
  std::cout << "Sequential access reset to address 0x" << std::hex << new_start_addr << std::dec << std::endl;
}
