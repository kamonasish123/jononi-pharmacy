# Jononi Pharmacy 💊

Jononi Pharmacy is a full-featured **Flutter-based pharmacy management application** designed to simplify daily pharmacy operations such as medicine stock management, sales tracking, customer dues, and low-stock monitoring.  
The app is built with **Firebase** and follows clean UI and scalable architecture principles.

---

## 🚀 Features

### 🔐 Authentication & Roles
- Firebase Authentication (Email & Password)
- Role-based access (Admin / Staff)
- Persistent login (no re-login unless user logs out)

### 💊 Medicine Management
- Add, edit, and delete medicines
- Track initial quantity and remaining stock
- Prevent negative stock updates
- Low-stock warning system

### 🏪 Sales & Billing
- Sell medicines with automatic stock deduction
- Validation to prevent selling more than available stock
- Real-time stock updates after sales

### 📊 Stock & Reports
- Low stock list
- Customer due list
- Company-wise medicine listing

### 🧾 Company Management
- Add and manage medicine companies
- View company-wise inventory

### 👥 Customer Management
- Track customer dues
- View pending payments

### 📱 UI/UX Improvements
- Mobile-friendly UI
- Clear user list layout (Name, Email, Role, Revoke option)
- Optimized for real pharmacy usage

---

## 🛠 Tech Stack

- **Frontend:** Flutter (Dart)
- **Backend:** Firebase
    - Firebase Authentication
    - Cloud Firestore
- **State Management:** SetState (can be upgraded easily)
- **Platform:** Android (APK)

---
## 📱 Live Demo

Try the app directly in your web browser (no installation needed):

👉 [Click here to launch the live demo](https://appetize.io/app/b_z2tyekdswt26yho43jjqxk43gu)

**Demo Login**
- Email: `demo@jononi.com`
- Password: `demo1234`
---
## 📦 APK

A fresh production-ready APK is generated and tested.  
(Available on request or via GitHub Releases.)

---

## 🧪 Tested Scenarios

- App restart without logout keeps user logged in
- Stock never goes negative
- Sales blocked if insufficient stock
- Stable behavior after app reinstall

---

## 🧑‍💻 Developer

**Kamonasish Roy**  
📧 Email: rkamonasish@gmail.com  
🌐 GitHub: https://github.com/kamonasish123

---

## 📌 Notes for HR / Reviewers

- This project demonstrates **real-world business logic**
- Focused on **data integrity**, **validation**, and **usability**
- Easily extendable with:
    - bKash / payment gateway integration
    - PDF invoice generation
    - Admin dashboard & analytics

---

## 📜 License

This project is for learning, demonstration, and portfolio purposes.
