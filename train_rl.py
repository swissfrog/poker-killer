"""
Otto Poker RL Training Script v2
==================================
Sauber und getestet für RLCard DQNAgent
"""

import os
import torch
import numpy as np

# ── Install ───────────────────────────────────────────────────────────────────
try:
    import rlcard
except ImportError:
    os.system("pip install rlcard -q")
    import rlcard

from rlcard.agents import DQNAgent, RandomAgent
from rlcard.utils import set_seed, tournament, Logger

# ── Config ────────────────────────────────────────────────────────────────────
GAME        = 'no-limit-holdem'
NUM_PLAYERS = 2
TRAIN_STEPS = 2_000_000
EVAL_EVERY  = 10_000
EVAL_GAMES  = 500
SAVE_PATH   = './otto_model'
LOG_DIR     = './otto_logs'
SEED        = 42
BATCH_SIZE  = 64

set_seed(SEED)
os.makedirs(SAVE_PATH, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

# ── Environment ───────────────────────────────────────────────────────────────
env      = rlcard.make(GAME, config={'seed': SEED, 'num_players': NUM_PLAYERS})
eval_env = rlcard.make(GAME, config={'seed': SEED+1, 'num_players': NUM_PLAYERS})

state_dim  = env.state_shape[0][0]
action_dim = env.num_actions

print(f"✅ Environment: {GAME}")
print(f"   State dim: {state_dim} | Actions: {action_dim}")

# ── Agent ─────────────────────────────────────────────────────────────────────
agent = DQNAgent(
    num_actions=action_dim,
    state_shape=state_dim,
    mlp_layers=[256, 256, 128],
    learning_rate=2e-4,
    batch_size=BATCH_SIZE,
    replay_memory_size=20_000,
    replay_memory_init_size=BATCH_SIZE,  # nur batch_size nötig zum starten
    train_every=1,
    epsilon_start=1.0,
    epsilon_end=0.05,
    epsilon_decay_steps=500_000,
)

rand_agent = RandomAgent(num_actions=action_dim)
env.set_agents([agent, rand_agent])
eval_env.set_agents([agent, rand_agent])

print(f"\n🎯 Training: {TRAIN_STEPS:,} Steps")

# ── Replay Buffer vorwärmen ───────────────────────────────────────────────────
print("   Vorwärmen des Replay Buffers...")
warmup = 0
while warmup < BATCH_SIZE * 2:
    traj, _ = env.run(is_training=False)
    for i in range(0, len(traj[0]) - 2, 2):
        s = traj[0][i]
        if not isinstance(s, dict): continue
        a = traj[0][i+1]
        ns = traj[0][i+2] if i+2 < len(traj[0]) and isinstance(traj[0][i+2], dict) else s
        done = not (i+2 < len(traj[0]) and isinstance(traj[0][i+2], dict))
        r = float(ns['raw_obs'].get('my_chips', 0)) - float(s['raw_obs'].get('my_chips', 0))
        agent.feed_memory(s['obs'], a, r, ns['obs'], list(ns['legal_actions'].keys()), done)
        warmup += 1
print(f"   Buffer: {warmup} Einträge")

# ── Training Loop ─────────────────────────────────────────────────────────────
best_reward = -float('inf')

with Logger(LOG_DIR) as logger:
    for step in range(TRAIN_STEPS):

        # Spiel spielen
        traj, _ = env.run(is_training=True)
        for i in range(0, len(traj[0]) - 2, 2):
            s = traj[0][i]
            if not isinstance(s, dict): continue
            a = traj[0][i+1]
            ns = traj[0][i+2] if i+2 < len(traj[0]) and isinstance(traj[0][i+2], dict) else s
            done = not (i+2 < len(traj[0]) and isinstance(traj[0][i+2], dict))
            r = float(ns['raw_obs'].get('my_chips', 0)) - float(s['raw_obs'].get('my_chips', 0))
            agent.feed_memory(s['obs'], a, r, ns['obs'], list(ns['legal_actions'].keys()), done)

        # Trainieren
        agent.train()

        # Evaluierung
        if step % EVAL_EVERY == 0:
            rewards, _ = tournament(eval_env, EVAL_GAMES)
            avg = rewards[0] if hasattr(rewards, '__len__') else float(rewards)
            eps = agent.epsilons[0] if hasattr(agent, 'epsilons') else 0
            print(f"  Step {step:>8,} | Reward: {avg:+.4f} | Epsilon: {eps:.3f}")
            logger.log_performance(step, avg)

            if avg > best_reward:
                best_reward = avg
                torch.save(agent.q_estimator.qnet.state_dict(),
                           os.path.join(SAVE_PATH, 'model.pth'))
                print(f"  💾 Bestes Modell gespeichert ({best_reward:+.4f})")

        # Self-Play ab Hälfte
        if step == TRAIN_STEPS // 2:
            print("\n🔄 Wechsel zu Self-Play...")
            sp = DQNAgent(num_actions=action_dim, state_shape=state_dim,
                          mlp_layers=[256, 256, 128])
            sp.q_estimator.qnet.load_state_dict(
                torch.load(os.path.join(SAVE_PATH, 'model.pth'), map_location='cpu'))
            env.set_agents([agent, sp])

print(f"\n✅ Training fertig! Bestes Reward: {best_reward:+.4f}")
print(f"   Modell: {SAVE_PATH}/model.pth")

# ── TFLite Export ─────────────────────────────────────────────────────────────
print("\n📦 Exportiere TFLite...")
try:
    import tensorflow as tf

    # Torch → ONNX
    qnet = agent.q_estimator.qnet
    qnet.eval()
    dummy = torch.randn(1, state_dim)
    torch.onnx.export(qnet, dummy, 'otto.onnx',
                      input_names=['state'], output_names=['q_values'],
                      dynamic_axes={'state': {0: 'batch'}})

    # ONNX → TF → TFLite
    import onnx
    from onnx_tf.backend import prepare
    onnx_model = onnx.load('otto.onnx')
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph('otto_tf')

    converter = tf.lite.TFLiteConverter.from_saved_model('otto_tf')
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite = converter.convert()
    with open('poker_brain_rl.tflite', 'wb') as f:
        f.write(tflite)

    kb = os.path.getsize('poker_brain_rl.tflite') / 1024
    print(f"✅ poker_brain_rl.tflite ({kb:.0f} KB)")
    print("   → Lade die Datei runter und ersetze poker_brain.tflite in der App!")

except Exception as e:
    print(f"⚠️  TFLite Export fehlgeschlagen: {e}")
    print(f"   PyTorch Modell liegt in: {SAVE_PATH}/model.pth")
