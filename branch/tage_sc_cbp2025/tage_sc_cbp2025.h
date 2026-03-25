#ifndef BRANCH_TAGE_SC_CBP2025_H
#define BRANCH_TAGE_SC_CBP2025_H

#include "modules.h"

class tage_sc_cbp2025 : champsim::modules::branch_predictor
{
    bool pred_taken = false;  // predict_branch() result, consumed by last_branch_result()

public:
    using branch_predictor::branch_predictor;  // Inherit constructor

    bool predict_branch(uint64_t ip, uint64_t predicted_target, bool always_taken, uint8_t branch_type);
    void last_branch_result(uint64_t ip, uint64_t branch_target, bool taken, uint8_t branch_type);
};

#endif
