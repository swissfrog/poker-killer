"""
Otto Poker RL Training Script
==============================
Self-Play Reinforcement Learning für Texas Hold'em (No-Limit)
Läuft auf RunPod / Google Colab mit GPU

Output: poker_brain_rl.tflite (drop-in Ersatz für poker_brain.tflite)

Setup:
    pip install rlcard torch tensorflow
"""

import os
import random
import numpy as np

# ── RLCard Setup ──────────────────────────────────────────────────────────────
try:
    import rlcard
    from rlcard.agents import DQNAgent, RandomAgent
    from rlcard.utils import set_seed, tournament, Logger
except ImportError:
    print("Installing rlcard...")
    os.system("pip install rlcard -q")
    import rlcard
    from rlcard.agents import DQNAgent, RandomAgent
    from rlcard.utils import set_seed, tournament, Logger

# ── Config ────────────────────────────────────────────────────────────────────
GAME         = 'no-limit-holdem'   # NL Hold'em
NUM_PLAYERS  = 2                   # Heads-Up (einfacher zu lernen)
TRAIN_STEPS  = 500_000             # Trainingsschritte (erhöhen für bessere Qualität)
EVAL_EVERY   = 10_000              # Alle X Steps evaluieren
EVAL_GAMES   = 1_000               # Spiele für Evaluation
SAVE_PATH    = './otto_model'      # Wo das Modell gespeichert wird
SEED         = 42
LOG_DIR      = './otto_logs'

set_seed(SEED)
os.makedirs(SAVE_PATH, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

# ── Environment ───────────────────────────────────────────────────────────────
env = rlcard.make(GAME, config={
    'seed': SEED,
    'num_players': NUM_PLAYERS,
})

eval_env = rlcard.make(GAME, config={
    'seed': SEED + 1,
    'num_players': NUM_PLAYERS,
})

print(f"✅ Environment: {GAME} ({NUM_PLAYERS} Spieler)")
print(f"   State shape:  {env.state_shape}")
print(f"   Action num:   {env.num_actions}")

# ── DQN Agent ─────────────────────────────────────────────────────────────────
agent = DQNAgent(
    num_actions=env.num_actions,
    state_shape=env.state_shape[0],
    mlp_layers=[256, 256, 128],    # Größeres Netz für bessere Spielstärke
    learning_rate=5e-4,
    batch_size=256,
    replay_memory_size=100_000,
    replay_memory_init_size=100,
    train_every=1,
    epsilon_start=1.0,
    epsilon_end=0.05,
    epsilon_decay_steps=100_000,
    device=None,                   # Auto: GPU wenn verfügbar, sonst CPU
)

# Gegner: zuerst Random, dann Self-Play
random_agent = RandomAgent(num_actions=env.num_actions)
env.set_agents([agent, random_agent])
eval_env.set_agents([agent, random_agent])

print(f"\n🎯 Training startet: {TRAIN_STEPS:,} Steps")
print(f"   Evaluierung alle {EVAL_EVERY:,} Steps\n")

# ── Training Loop ─────────────────────────────────────────────────────────────
best_reward = -float('inf')
rewards_history = []

with Logger(LOG_DIR) as logger:
    for step in range(TRAIN_STEPS):
        # Spiel spielen und Erfahrungen sammeln
        # RLCard trajectory format: [state, action, reward, state, action, reward, ..., state]
        # d.h. abwechselnd: state (dict), action (int), reward (float), state (dict), ...
        trajectories, _ = env.run(is_training=True)
        # RLCard format: [state, action, next_state, state, action, next_state, ...]
        traj = trajectories[0]
        i = 0
        while i + 2 < len(traj):
            state      = traj[i]
            action     = traj[i + 1]
            next_state = traj[i + 2]
            if not isinstance(state, dict) or not isinstance(next_state, dict):
                i += 1
                continue
            done = (i + 3 >= len(traj))
            reward = next_state.get('raw_obs', {}).get('my_chips', 0) - state.get('raw_obs', {}).get('my_chips', 0)
            agent.feed_memory(
                state['obs'],
                action,
                reward,
                next_state['obs'],
                list(next_state['legal_actions'].keys()),
                done,
            )
            i += 3

        # Erst trainieren wenn genug Daten im Buffer
        if step >= 100:
            agent.train()

        # Regelmäßige Evaluierung
        if step % EVAL_EVERY == 0:
            rewards, _ = tournament(eval_env, EVAL_GAMES)
            avg_reward = rewards[0]
            rewards_history.append(avg_reward)

            print(f"  Step {step:>8,} | Reward: {avg_reward:+.4f} | Epsilon: {agent.epsilon:.3f}")
            logger.log_performance(step, avg_reward)

            # Bestes Modell speichern
            if avg_reward > best_reward:
                best_reward = avg_reward
                agent.save(SAVE_PATH)
                print(f"  💾 Neues bestes Modell gespeichert (Reward: {best_reward:+.4f})")

        # Nach Hälfte: Self-Play statt Random Gegner
        if step == TRAIN_STEPS // 2:
            print("\n🔄 Wechsel zu Self-Play Training...")
            self_play_agent = DQNAgent(
                num_actions=env.num_actions,
                state_shape=env.state_shape[0],
                mlp_layers=[256, 256, 128],
                learning_rate=5e-4,
                batch_size=256,
                replay_memory_size=100_000,
                replay_memory_init_size=100,
            )
            self_play_agent.load(SAVE_PATH)
            env.set_agents([agent, self_play_agent])

print(f"\n✅ Training abgeschlossen!")
print(f"   Bestes Reward: {best_reward:+.4f}")
print(f"   Modell gespeichert: {SAVE_PATH}")

# ── TFLite Export ─────────────────────────────────────────────────────────────
print("\n📦 Exportiere als TFLite...")

try:
    import torch
    import tensorflow as tf

    # PyTorch Modell laden
    checkpoint = torch.load(os.path.join(SAVE_PATH, 'model.pth'), map_location='cpu')
    state_dict = checkpoint

    # Modell-Architektur nachbauen
    class OttoNet(torch.nn.Module):
        def __init__(self, state_dim, action_dim):
            super().__init__()
            self.net = torch.nn.Sequential(
                torch.nn.Linear(state_dim, 256),
                torch.nn.ReLU(),
                torch.nn.Linear(256, 256),
                torch.nn.ReLU(),
                torch.nn.Linear(256, 128),
                torch.nn.ReLU(),
                torch.nn.Linear(128, action_dim),
                torch.nn.Softmax(dim=-1),
            )
        def forward(self, x):
            return self.net(x)

    state_dim  = env.state_shape[0][0]
    action_dim = env.num_actions

    model = OttoNet(state_dim, action_dim)
    model.load_state_dict(state_dict, strict=False)
    model.eval()

    # ONNX Export
    dummy = torch.randn(1, state_dim)
    onnx_path = 'otto_poker.onnx'
    torch.onnx.export(model, dummy, onnx_path,
                      input_names=['state'],
                      output_names=['action_probs'],
                      dynamic_axes={'state': {0: 'batch'}})
    print(f"  ✅ ONNX: {onnx_path}")

    # TFLite via tf.lite
    import onnx
    from onnx_tf.backend import prepare

    onnx_model = onnx.load(onnx_path)
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph('otto_tf_model')

    converter = tf.lite.TFLiteConverter.from_saved_model('otto_tf_model')
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()

    tflite_path = 'poker_brain_rl.tflite'
    with open(tflite_path, 'wb') as f:
        f.write(tflite_model)

    size_kb = os.path.getsize(tflite_path) / 1024
    print(f"  ✅ TFLite: {tflite_path} ({size_kb:.0f} KB)")
    print(f"\n🎉 Fertig! Lade '{tflite_path}' runter und ersetze 'poker_brain.tflite' in der App.")

except Exception as e:
    print(f"\n⚠️  TFLite Export fehlgeschlagen: {e}")
    print(f"   Das PyTorch Modell liegt in: {SAVE_PATH}/")
    print(f"   Manueller Export nötig.")
