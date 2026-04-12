// Jimenez MPP on top of the bundled CBP2016 TAGE-SC-L core.
// Keep the internal *.inc files in this TU only, and keep the include order.
// Avoid unqualified branch_predictor here because the bundled code defines a global one.

#include "mpp_cbp2025.h"
#include "instruction.h"

#include "internal/sim_common_structs.inc"
#include "internal/cbp2016_tage_sc_l.inc"
#include "internal/my_cond_branch_predictor.inc"

namespace
{
// Keep BRANCH_OTHER non-conditional so stale pred_taken never enters conditional history handling.
static int champsim_to_cbp_brtype(uint8_t branch_type)
{
  switch (branch_type) {
  case BRANCH_DIRECT_JUMP:
    return 0; // uncond direct
  case BRANCH_INDIRECT:
    return 2; // uncond indirect
  case BRANCH_CONDITIONAL:
    return 1; // cond
  case BRANCH_DIRECT_CALL:
    return 0; // uncond direct (call)
  case BRANCH_INDIRECT_CALL:
    return 2; // uncond indirect (call)
  case BRANCH_RETURN:
    return 2; // uncond indirect (return)
  case BRANCH_OTHER:
    return 2; // safe non-conditional fallback
  default:
    return 2;
  }
}

// BRANCH_OTHER uses the same indirect fallback here.
static InstClass champsim_to_inst_class(uint8_t branch_type)
{
  switch (branch_type) {
  case BRANCH_DIRECT_JUMP:
    return InstClass::uncondDirectBranchInstClass;
  case BRANCH_INDIRECT:
    return InstClass::uncondIndirectBranchInstClass;
  case BRANCH_CONDITIONAL:
    return InstClass::condBranchInstClass;
  case BRANCH_DIRECT_CALL:
    return InstClass::callDirectInstClass;
  case BRANCH_INDIRECT_CALL:
    return InstClass::callIndirectInstClass;
  case BRANCH_RETURN:
    return InstClass::ReturnInstClass;
  case BRANCH_OTHER:
    return InstClass::uncondIndirectBranchInstClass;
  default:
    return InstClass::uncondIndirectBranchInstClass;
  }
}
} // namespace

// Keep the combined predictor order: TAGE-SC-L first, then MPP.
bool mpp_cbp2025::predict_branch(uint64_t ip, uint64_t /*predicted_target*/, bool always_taken, uint8_t branch_type)
{
  if (branch_type == BRANCH_CONDITIONAL) {
    const bool tage_pred = cbp2016_tage_sc_l.predict(0, 0, ip);
    pred_taken = cond_predictor_impl.predict(0, 0, ip, tage_pred);
    return pred_taken;
  }
  return always_taken;
}

// Keep the history/update order aligned with the combined predictor.
void mpp_cbp2025::last_branch_result(uint64_t ip, uint64_t branch_target, uint64_t next_ip, bool taken, uint8_t branch_type)
{
  const int brtype = champsim_to_cbp_brtype(branch_type);
  const uint64_t nextPC = taken ? branch_target : next_ip; // Use next_ip for not-taken branches.

  if (branch_type == BRANCH_CONDITIONAL) {
    cbp2016_tage_sc_l.history_update(0, 0, ip, brtype, pred_taken, taken, nextPC);
    cond_predictor_impl.history_update(0, 0, ip, taken, nextPC);
    cbp2016_tage_sc_l.update(0, 0, ip, taken, pred_taken, nextPC);
    cond_predictor_impl.update(0, 0, ip, taken, pred_taken, nextPC);
  } else {
    cbp2016_tage_sc_l.TrackOtherInst(ip, brtype, pred_taken, taken, nextPC);
    cond_predictor_impl.nonconditional_history_update(0, 0, ip, taken, nextPC, champsim_to_inst_class(branch_type));
  }
}
