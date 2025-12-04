<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

class CreateAdminUser extends Command
{
    protected $signature = 'user:create-admin';
    protected $description = 'Crée un utilisateur administrateur par défaut';

    public function handle()
    {
        // Vérifier si l'admin existe déjà
        if (User::where('email', 'admin@example.com')->exists()) {
            $this->warn('⚠️  L\'utilisateur admin existe déjà');
            return Command::SUCCESS;
        }

        try {
            User::create([
                'name' => 'Admin',
                'email' => 'admin@example.com',
                'password' => Hash::make('password'),
                'telephone' => '0000000000',
                'role' => User::ROLE_ADMIN,
                'actif' => true,
                'email_verified_at' => now(),
            ]);

            $this->info('✅ Utilisateur admin créé avec succès !');
            $this->info('📧 Email: admin@example.com');
            $this->info('🔑 Mot de passe: password');
            $this->warn('⚠️  CHANGEZ CE MOT DE PASSE IMMÉDIATEMENT !');

            return Command::SUCCESS;
        } catch (\Exception $e) {
            $this->error('❌ Erreur lors de la création de l\'admin: ' . $e->getMessage());
            return Command::FAILURE;
        }
    }
}
