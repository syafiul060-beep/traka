/**
 * Script untuk membuat akun demo Google Play.
 * Jalankan: cd traka/functions && node scripts/create-demo-account.js
 *
 * Pastikan: Buat serviceAccountKey.json dari Firebase Console > Project Settings >
 * Service Accounts > Generate new private key, simpan di functions/
 */

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'syafiul-traka';

if (!admin.apps.length) {
  const keyPath = path.join(__dirname, '..', 'serviceAccountKey.json');
  const fs = require('fs');
  if (fs.existsSync(keyPath)) {
    const serviceAccount = require(keyPath);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount), projectId: PROJECT_ID });
  } else {
    console.error('File serviceAccountKey.json tidak ditemukan di folder functions/');
    console.error('Buat dari Firebase Console > Project Settings > Service Accounts > Generate new private key');
    console.error('Simpan sebagai: traka/functions/serviceAccountKey.json');
    process.exit(1);
  }
}

const auth = admin.auth();
const firestore = admin.firestore();

const DEMO_EMAIL = 'demo@traka.app';
const DEMO_PASSWORD = 'Demo123!';
const DEMO_NAME = 'Demo Penumpang';

async function main() {
  console.log('Membuat akun demo untuk Google Play review...\n');

  try {
    let user;
    try {
      user = await auth.getUserByEmail(DEMO_EMAIL);
      console.log('Email sudah terdaftar. Update Firestore...');
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        user = await auth.createUser({
          email: DEMO_EMAIL,
          password: DEMO_PASSWORD,
          displayName: DEMO_NAME,
          emailVerified: true,
        });
        console.log('Akun Firebase Auth dibuat:', user.uid);
      } else {
        throw e;
      }
    }

    const uid = user.uid;

    const userData = {
      role: 'penumpang',
      email: DEMO_EMAIL,
      displayName: DEMO_NAME,
      photoUrl: '',
      faceVerificationUrl: 'https://ui-avatars.com/api/?name=Demo&size=200',
      faceVerificationPool: [{ url: 'https://ui-avatars.com/api/?name=Demo&size=200', width: 200, height: 200 }],
      deviceId: 'demo_reviewer',
      isDemoAccount: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await firestore.collection('users').doc(uid).set(userData, { merge: true });
    console.log('Dokumen Firestore users/' + uid + ' dibuat/diupdate.');

    console.log('\n=== AKUN DEMO SIAP ===');
    console.log('Email   :', DEMO_EMAIL);
    console.log('Password:', DEMO_PASSWORD);
    console.log('\nIsi di Play Console > App content > App access > Login credentials');
    console.log('================================\n');
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  } finally {
    process.exit(0);
  }
}

main();
