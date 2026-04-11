#include "tage_sc_cbp2025.h"
#include "my_cond_branch_predictor.inc"  // CBP2025 code (global cbp2025 instance at line 2271; .inc to avoid ChampSim auto-include)
#include "instruction.h"               // BRANCH_* constants

// CBP2025 predictor instance: defined as `static CBP2025 cbp2025;` at the end of my_cond_branch_predictor.inc (line 2271).

// ChampSim branch_type -> CBP2025 brtype conversion 
static int champsim_to_cbp_brtype(uint8_t branch_type)
{
    int brtype = 0;
    switch (branch_type) {
        case BRANCH_INDIRECT:       // 1
        case BRANCH_INDIRECT_CALL:  // 4
        case BRANCH_RETURN:         // 5
        case BRANCH_OTHER:          // 6
            brtype = 2;
            break;
        default:  // BRANCH_DIRECT_JUMP(0), BRANCH_CONDITIONAL(2), BRANCH_DIRECT_CALL(3)
            brtype = 0;
            break;
    }
    switch (branch_type) {
        case BRANCH_CONDITIONAL:  // 2
        case BRANCH_OTHER:        // 6
            brtype += 1;
            break;
    }
    return brtype;
}

bool tage_sc_cbp2025::predict_branch(uint64_t ip, uint64_t predicted_target,
                                      bool always_taken, uint8_t branch_type)
{
    if (branch_type == BRANCH_CONDITIONAL) {
        pred_taken = cbp2025.predict(0, 0, ip);
        return pred_taken;
    }
    // Non-conditional branch: follow BTB prediction
    return always_taken;
}

void tage_sc_cbp2025::last_branch_result(uint64_t ip, uint64_t branch_target,
                                          uint64_t next_ip, bool taken, uint8_t branch_type)
{
    int brtype = champsim_to_cbp_brtype(branch_type);
    uint64_t nextPC = taken ? branch_target : next_ip;  // exact nextPC

    if (branch_type == BRANCH_CONDITIONAL) {
        // update(): train TAGE/SC tables using actual outcome
        // HistoryUpdate(): update global/path history — must be called separately
        cbp2025.update(ip, taken, pred_taken, branch_target, cbp2025.active_hist);
        cbp2025.HistoryUpdate(ip, brtype, taken, nextPC);
    } else {
        // Non-conditional: skip table training, but record in global/path history
        cbp2025.TrackOtherInst(ip, brtype, taken, nextPC);
    }
}
