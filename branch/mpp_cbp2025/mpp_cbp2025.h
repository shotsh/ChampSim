#ifndef BRANCH_MPP_CBP2025_H
#define BRANCH_MPP_CBP2025_H

#include <cstdint>

#include "modules.h"

// Keep the bundled internal code out of the header so it stays in one translation unit.
class mpp_cbp2025 : champsim::modules::branch_predictor
{
  bool pred_taken = false; // Carries the conditional prediction into last_branch_result().

public:
  using branch_predictor::branch_predictor; // Inherit constructor

  bool predict_branch(uint64_t ip, uint64_t predicted_target, bool always_taken, uint8_t branch_type);
  void last_branch_result(uint64_t ip, uint64_t branch_target, bool taken, uint8_t branch_type);
};

#endif // BRANCH_MPP_CBP2025_H
