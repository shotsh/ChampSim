#include "tage_sc_cbp2025.h"
#include "my_cond_branch_predictor.h"
#include "instruction.h"

// Map ChampSim branch_type to CBP brtype: bit1=indirect, bit0=conditional
static int champsim_to_cbp_brtype(uint8_t branch_type)
{
    int brtype = 0;
    switch (branch_type) {
        case BRANCH_INDIRECT:
        case BRANCH_INDIRECT_CALL:
        case BRANCH_RETURN:
        case BRANCH_OTHER:
            brtype = 2;
            break;
        default:
            brtype = 0;
            break;
    }
    switch (branch_type) {
        case BRANCH_CONDITIONAL:
        case BRANCH_OTHER:
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
    return always_taken;
}

void tage_sc_cbp2025::last_branch_result(uint64_t ip, uint64_t branch_target,
                                          bool taken, uint8_t branch_type)
{
    int brtype = champsim_to_cbp_brtype(branch_type);

    if (branch_type == BRANCH_CONDITIONAL) {
        // update(): train TAGE/SC tables using actual outcome
        // HistoryUpdate(): update global/path history — must be called separately
        cbp2025.update(ip, taken, pred_taken, branch_target, cbp2025.active_hist);
        cbp2025.HistoryUpdate(ip, brtype, taken, branch_target);
    } else {
        // Non-conditional: skip table training, but record in global/path history
        cbp2025.TrackOtherInst(ip, brtype, taken, branch_target);
    }
}
