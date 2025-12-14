const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

let vehicles = [];
let durations = [];
let payments = [];
let currentVehicle = null;
let selectedDuration = null;
let selectedPayment = null;
let locationIndex = 1;
let favorites = JSON.parse(localStorage.getItem('rental_favorites') || '[]');

const el = {
    carGrid: $('#car-grid'),
    emptyState: $('#empty-state'),
    searchInput: $('#search-input'),
    filterFavorites: $('#filter-favorites'),
    closeBtn: $('#close-btn'),
    modal: $('.details-panel.modal'),
    overlay: $('.modal-overlay'),
    closeModal: $('.close-modal'),
    modalName: $('#modal-name'),
    modalManufacturer: $('#modal-manufacturer'),
    modalImage: $('#modal-image'),
    modalCategory: $('#modal-category'),
    modalPrice: $('#modal-price'),
    modalStats: $('#modal-stats'),
    totalPrice: $('#total-price'),
    durationDropdown: $('#duration-dropdown'),
    durationMenu: $('#duration-menu'),
    paymentDropdown: $('#payment-dropdown'),
    paymentMenu: $('#payment-menu'),
    confirmBtn: $('#confirm-btn'),
};


function post(eventName, data = {}) {
    return fetch(`https://${getResourceName()}/${eventName}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function getResourceName() {
    if (typeof window.GetParentResourceName === 'function') {
        try {
            return window.GetParentResourceName();
        } catch (e) {
            return 'F4-Rental';
        }
    }
    return 'F4-Rental';
}

window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
        case 'open':
            openUI(data);
            break;
        case 'close':
            closeUI();
            break;
        case 'openContract':
            openContract(data.contract);
            break;
        case 'receiveMyRentals':
            handleReceiveMyRentals(data.rentals);
            break;
    }
});

function openUI(data) {
    vehicles = data.vehicles || [];
    durations = data.durations || [];
    payments = data.payments || [];
    locationIndex = data.locationIndex || 1;

    selectedDuration = durations[0] || { days: 1, label: '1 Day', multiplier: 1.0 };
    selectedPayment = payments[0] || { id: 'bank', label: 'Bank Transfer', icon: 'fa-credit-card' };

    renderVehicles(vehicles);
    renderDurations();
    renderPayments();

    $('.container').style.display = 'flex';
    el.modal.style.display = 'none';
    el.overlay.style.display = 'none';
    el.modal.classList.remove('active');
    el.overlay.classList.remove('active');

    if (contractPanel) {
        contractPanel.style.display = 'none';
        contractPanel.classList.remove('active');
    }
    if (contractOverlay) {
        contractOverlay.style.display = 'none';
        contractOverlay.classList.remove('active');
    }

    document.body.style.display = 'flex';
}

function closeUI() {
    toggleModal(false);
    post('close').then(() => {
        document.body.style.display = 'none';
    }).catch(() => {
        document.body.style.display = 'none';
    });
}


function renderVehicles(vehicleList) {
    el.carGrid.innerHTML = '';

    if (vehicleList.length === 0) {
        el.emptyState.style.display = 'flex';
        el.carGrid.appendChild(el.emptyState);
        return;
    }

    el.emptyState.style.display = 'none';

    vehicleList.forEach((vehicle, index) => {
        const isFavorite = favorites.includes(vehicle.model);
        const carItem = document.createElement('div');
        carItem.className = 'car-item' + (index === 0 ? ' active' : '');
        carItem.dataset.model = vehicle.model;
        carItem.dataset.category = vehicle.category;

        carItem.innerHTML = `
            <div class="car-header">
                <div class="car-names">
                    <span class="car-sub">${vehicle.manufacturer}</span>
                    <span class="car-name">${vehicle.label}</span>
                </div>
                <i class="fa-${isFavorite ? 'solid' : 'regular'} fa-star" 
                   style="color: ${isFavorite ? '#e67e22' : ''}; cursor: pointer;"></i>
            </div>
            <img src="${vehicle.image}" alt="${vehicle.label}" onerror="this.src='https://docs.fivem.net/vehicles/${vehicle.model}.webp'">
            <div class="car-price">$${vehicle.price}/day</div>
            <div class="car-actions">
                <button class="btn-select"><i class="fa-solid fa-hand-pointer"></i> Select</button>
            </div>
        `;

        carItem.addEventListener('click', (e) => {
            $$('.car-item').forEach(c => c.classList.remove('active'));
            carItem.classList.add('active');

            if (e.target.closest('.btn-select')) {
                currentVehicle = vehicle;
                updateModal(vehicle);
                toggleModal(true);
            }
        });

        const starIcon = carItem.querySelector('.fa-star');
        starIcon.addEventListener('click', (e) => {
            e.stopPropagation();
            toggleFavorite(vehicle.model, starIcon);
        });

        el.carGrid.appendChild(carItem);
    });

    if (vehicleList.length > 0) {
        currentVehicle = vehicleList[0];
    }
}

function renderDurations() {
    el.durationMenu.innerHTML = '';

    durations.forEach((duration, index) => {
        const item = document.createElement('div');
        item.className = 'dropdown-item' + (index === 0 ? ' active' : '');
        item.dataset.value = duration.days;
        item.dataset.multiplier = duration.multiplier;
        item.innerHTML = `<span>${duration.label}</span>`;

        item.addEventListener('click', (e) => {
            e.stopPropagation();
            $$('#duration-menu .dropdown-item').forEach(i => i.classList.remove('active'));
            item.classList.add('active');
            selectedDuration = duration;

            el.durationDropdown.querySelector('.dropdown-trigger span').textContent = duration.label;
            el.durationDropdown.classList.remove('open');

            updateTotalPrice();
        });

        el.durationMenu.appendChild(item);
    });

    if (durations.length > 0) {
        el.durationDropdown.querySelector('.dropdown-trigger span').textContent = durations[0].label;
    }
}

function renderPayments() {
    el.paymentMenu.innerHTML = '';

    payments.forEach((payment, index) => {
        const item = document.createElement('div');
        item.className = 'dropdown-item' + (index === 0 ? ' active' : '');
        item.dataset.value = payment.id;
        item.innerHTML = `<i class="fa-solid ${payment.icon}"></i><span>${payment.label}</span>`;

        item.addEventListener('click', (e) => {
            e.stopPropagation();
            $$('#payment-menu .dropdown-item').forEach(i => i.classList.remove('active'));
            item.classList.add('active');
            selectedPayment = payment;

            el.paymentDropdown.querySelector('.dropdown-trigger span').innerHTML =
                `<i class="fa-solid ${payment.icon}"></i> ${payment.label}`;
            el.paymentDropdown.classList.remove('open');
        });

        el.paymentMenu.appendChild(item);
    });

    if (payments.length > 0) {
        el.paymentDropdown.querySelector('.dropdown-trigger span').innerHTML =
            `<i class="fa-solid ${payments[0].icon}"></i> ${payments[0].label}`;
    }
}


function toggleModal(show) {
    if (show) {
        el.modal.style.display = 'flex';
        el.overlay.style.display = 'block';
        requestAnimationFrame(() => {
            el.modal.classList.add('active');
            el.overlay.classList.add('active');
        });
    } else {
        el.modal.classList.remove('active');
        el.overlay.classList.remove('active');
        setTimeout(() => {
            el.modal.style.display = 'none';
            el.overlay.style.display = 'none';
        }, 300);
    }
}

function updateModal(vehicle) {
    if (!vehicle) return;

    el.modalName.textContent = vehicle.label.toUpperCase();
    el.modalManufacturer.textContent = vehicle.manufacturer.toUpperCase();
    el.modalCategory.textContent = vehicle.category;
    el.modalPrice.innerHTML = `$${vehicle.price}<span class="per-day">/day</span>`;

    el.modalImage.style.opacity = '0';
    setTimeout(() => {
        el.modalImage.src = vehicle.image;
        el.modalImage.onerror = () => {
            el.modalImage.src = `https://docs.fivem.net/vehicles/${vehicle.model}.webp`;
        };
        el.modalImage.style.opacity = '1';
    }, 150);

    if (vehicle.stats) {
        updateStat('speed', vehicle.stats.speed);
        updateStat('acceleration', vehicle.stats.acceleration);
        updateStat('braking', vehicle.stats.braking);
        updateStat('handling', vehicle.stats.handling);
    }

    updateTotalPrice();
}

function updateStat(statName, value) {
    const statRow = el.modalStats.querySelector(`[data-stat="${statName}"]`);
    if (statRow) {
        statRow.querySelector('.stat-val').textContent = `${value}%`;
        statRow.querySelector('.stat-fill').style.width = `${value}%`;
    }
}

function updateTotalPrice() {
    if (!currentVehicle || !selectedDuration) return;

    const hours = selectedDuration.hours || 24;
    const hourlyRate = currentVehicle.price / 24;
    const total = Math.round(hourlyRate * hours);

    el.totalPrice.querySelector('span').textContent = `$${total}`;
}


function toggleFavorite(model, icon) {
    const index = favorites.indexOf(model);

    if (index > -1) {
        favorites.splice(index, 1);
        icon.classList.remove('fa-solid');
        icon.classList.add('fa-regular');
        icon.style.color = '';
    } else {
        favorites.push(model);
        icon.classList.remove('fa-regular');
        icon.classList.add('fa-solid');
        icon.style.color = '#e67e22';
    }

    localStorage.setItem('rental_favorites', JSON.stringify(favorites));
    filterVehicles();
}

function filterVehicles() {
    const searchTerm = el.searchInput.value.toLowerCase();
    const showFavoritesOnly = el.filterFavorites.classList.contains('active');

    const filtered = vehicles.filter(v => {
        const matchesSearch =
            v.label.toLowerCase().includes(searchTerm) ||
            v.manufacturer.toLowerCase().includes(searchTerm) ||
            v.category.toLowerCase().includes(searchTerm);

        const matchesFavorite = !showFavoritesOnly || favorites.includes(v.model);

        return matchesSearch && matchesFavorite;
    });

    renderVehicles(filtered);
}

function showNotification(title, message, type = 'success') {
    const container = $('#notification-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `notification-toast ${type}`;
    toast.innerHTML = `
                <i class="fa-solid ${type === 'success' ? 'fa-circle-check' : 'fa-circle-xmark'}"></i>
                    <div>
                        <span class="title">${title}</span>
                        <span class="message">${message}</span>
                    </div>
            `;

    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));

    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}


el.closeBtn?.addEventListener('click', closeUI);
el.closeModal?.addEventListener('click', () => toggleModal(false));
el.overlay?.addEventListener('click', () => toggleModal(false));
el.searchInput?.addEventListener('input', filterVehicles);

el.filterFavorites?.addEventListener('click', () => {
    el.filterFavorites.classList.toggle('active');
    filterVehicles();
});

el.durationDropdown?.addEventListener('click', (e) => {
    e.stopPropagation();
    el.paymentDropdown?.classList.remove('open');
    el.durationDropdown.classList.toggle('open');
});

el.paymentDropdown?.addEventListener('click', (e) => {
    e.stopPropagation();
    el.durationDropdown?.classList.remove('open');
    el.paymentDropdown.classList.toggle('open');
});

document.addEventListener('click', () => {
    el.durationDropdown?.classList.remove('open');
    el.paymentDropdown?.classList.remove('open');
});

el.confirmBtn?.addEventListener('click', () => {
    if (!currentVehicle || !selectedDuration || !selectedPayment) {
        showNotification('Error', 'Please select all options', 'error');
        return;
    }

    el.confirmBtn.disabled = true;
    el.confirmBtn.textContent = 'Processing...';

    post('confirmRental', {
        model: currentVehicle.model,
        duration: selectedDuration.hours || selectedDuration.days * 24,
        paymentMethod: selectedPayment.id,
        locationIndex: locationIndex,
    }).catch(() => { }).finally(() => {
        setTimeout(() => {
            if (el.confirmBtn) {
                el.confirmBtn.disabled = false;
                el.confirmBtn.textContent = 'Confirm Rental';
            }
        }, 2000);
    });
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (contractPanel?.classList.contains('active')) {
            closeContract();
        } else if (el.modal.classList.contains('active')) {
            toggleModal(false);
        } else {
            closeUI();
        }
    }
});

document.addEventListener('contextmenu', (e) => e.preventDefault());


const contractPanel = $('#contract-panel');
const contractOverlay = $('#contract-overlay');

function openContract(data) {
    if (!data) return;

    $('#contract-vehicle').textContent = data.vehicle || '-';
    $('#contract-model').textContent = data.model || '-';
    $('#contract-citizenid').textContent = data.citizenid || '-';
    $('#contract-id').textContent = data.rentalId || '000';

    const durationEl = $('#contract-duration');
    if (durationEl) {
        const hours = data.duration || 24;
        if (hours >= 24) {
            const days = Math.floor(hours / 24);
            const remainingHours = hours % 24;
            if (remainingHours > 0) {
                durationEl.textContent = `${days} Day${days > 1 ? 's' : ''} ${remainingHours} Hour${remainingHours > 1 ? 's' : ''}`;
            } else {
                durationEl.textContent = `${days} Day${days > 1 ? 's' : ''}`;
            }
        } else {
            durationEl.textContent = `${hours} Hour${hours > 1 ? 's' : ''}`;
        }
    }

    const startDate = data.startDate || '-';
    const endDate = data.endDate || '-';

    if (startDate.includes(' ')) {
        const [date, time] = startDate.split(' ');
        $('#contract-start').textContent = date || '-';
        const startTimeEl = $('#contract-start-time');
        if (startTimeEl) startTimeEl.textContent = time || '-';
    } else {
        $('#contract-start').textContent = startDate;
    }

    if (endDate.includes(' ')) {
        const [date, time] = endDate.split(' ');
        $('#contract-end').textContent = date || '-';
        const endTimeEl = $('#contract-end-time');
        if (endTimeEl) endTimeEl.textContent = time || '-';
    } else {
        $('#contract-end').textContent = endDate;
    }

    $('#contract-price').textContent = data.price ? `$${data.price.toLocaleString()}` : '$0';

    const paymentEl = $('#contract-payment');
    if (paymentEl) {
        const paymentMethod = data.paymentMethod || data.payment || '-';
        paymentEl.textContent = paymentMethod.charAt(0).toUpperCase() + paymentMethod.slice(1);
    }

    $('.container').style.display = 'none';
    el.modal.style.display = 'none';
    el.overlay.style.display = 'none';

    document.body.style.display = 'flex';
    contractOverlay.style.display = 'block';
    contractPanel.style.display = 'block';

    requestAnimationFrame(() => {
        contractOverlay.classList.add('active');
        contractPanel.classList.add('active');
    });
}

function closeContract() {
    contractOverlay.classList.remove('active');
    contractPanel.classList.remove('active');

    setTimeout(() => {
        contractOverlay.style.display = 'none';
        contractPanel.style.display = 'none';
        document.body.style.display = 'none';
    }, 300);

    post('closeContract');
}

$('#close-contract')?.addEventListener('click', closeContract);
contractOverlay?.addEventListener('click', closeContract);


const myRentalsPanel = $('#my-rentals-panel');
const rentalsList = $('#rentals-list');
const emptyRentals = $('#empty-rentals');
const tabBrowse = $('#tab-browse');
const tabMyRentals = $('#tab-myrentals');
const searchContainer = $('#search-container');

let currentTab = 'browse';
let rentalIntervals = [];

tabBrowse?.addEventListener('click', () => switchTab('browse'));
tabMyRentals?.addEventListener('click', () => switchTab('myrentals'));

function switchTab(tab) {
    currentTab = tab;

    tabBrowse?.classList.toggle('active', tab === 'browse');
    tabMyRentals?.classList.toggle('active', tab === 'myrentals');

    el.durationDropdown?.classList.remove('open');
    el.paymentDropdown?.classList.remove('open');

    if (tab === 'browse') {
        el.carGrid.style.display = 'grid';
        myRentalsPanel.style.display = 'none';
        searchContainer.style.visibility = 'visible';
        searchContainer.style.opacity = '1';
        clearRentalIntervals();
    } else {
        el.carGrid.style.display = 'none';
        myRentalsPanel.style.display = 'block';
        searchContainer.style.visibility = 'hidden';
        searchContainer.style.opacity = '0';
        loadMyRentals();
    }
}

function loadMyRentals() {
    rentalsList.innerHTML = '<div class="loading-spinner"><i class="fa-solid fa-spinner fa-spin"></i> Loading...</div>';
    emptyRentals.style.display = 'none';
    post('getMyRentals').catch(() => { });
}

function handleReceiveMyRentals(rentalsData) {
    let rentals = [];
    if (Array.isArray(rentalsData)) {
        rentals = rentalsData;
    } else if (typeof rentalsData === 'object' && rentalsData !== null) {
        rentals = Object.values(rentalsData);
    }

    rentals = rentals.filter(r => r && typeof r === 'object' && r.id);

    if (rentals.length === 0) {
        rentalsList.innerHTML = '';
        emptyRentals.style.display = 'flex';
        return;
    }

    renderRentals(rentals);
}

function clearRentalIntervals() {
    rentalIntervals.forEach(interval => clearInterval(interval));
    rentalIntervals = [];
}

function renderRentals(rentals) {
    rentalsList.innerHTML = '';
    emptyRentals.style.display = 'none';
    clearRentalIntervals();

    const rentalsArray = Array.isArray(rentals) ? rentals : [];

    if (rentalsArray.length === 0) {
        emptyRentals.style.display = 'flex';
        return;
    }

    rentalsArray.forEach(rental => {
        const card = document.createElement('div');
        card.className = 'rental-card';
        card.dataset.rentalId = rental.id;

        const vehicleConfig = vehicles.find(v => v.model === rental.model);
        const imageUrl = vehicleConfig?.image || `https://docs.fivem.net/vehicles/${rental.model}.webp`;
        const manufacturer = vehicleConfig?.manufacturer || 'Rental';

        const expiryDate = new Date(rental.endDate);
        const now = new Date();
        const timeLeft = expiryDate - now;
        const isExpired = timeLeft <= 0;
        const isExpiringSoon = !isExpired && timeLeft <= 5 * 60 * 1000;
        const isSpawned = rental.isSpawned;

        let statusClass = 'rental-status';
        let statusText = '';

        if (isExpired) {
            statusClass += ' expired';
            statusText = 'Overdue';
        } else if (isExpiringSoon) {
            statusClass += ' expiring';
            statusText = 'Expiring';
        } else if (isSpawned) {
            statusClass += ' spawned';
            statusText = 'Out';
        } else {
            statusClass += ' active';
            statusText = 'Stored';
        }

        card.innerHTML = `
            <div class="${statusClass}">${statusText}</div>
            
            <div class="car-header">
                <div class="car-names">
                    <span class="car-sub">${manufacturer}</span>
                    <span class="car-name">${rental.label}</span>
                </div>
            </div>

            <img src="${imageUrl}" alt="${rental.label}" onerror="this.src='https://docs.fivem.net/vehicles/${rental.model}.webp'">
            
            <div class="rental-info">
                <div class="rental-expiry ${isExpired ? 'expired' : ''} ${isExpiringSoon ? 'warning' : ''}">
                    <i class="fa-regular fa-clock"></i>
                    <span class="countdown-timer" data-end="${expiryDate.getTime()}">Calculating...</span>
                </div>
                ${rental.lateFeeTotal ? `<div class="late-fee-badge"><i class="fa-solid fa-exclamation-triangle"></i> $${rental.lateFeeTotal} fees</div>` : ''}
            </div>

            <button class="btn-retrieve" data-rental-id="${rental.id}" ${isSpawned ? 'disabled' : ''}>
                <i class="fa-solid fa-car"></i> ${isSpawned ? 'In Use' : 'Retrieve'}
            </button>
        `;

        const btn = card.querySelector('.btn-retrieve');
        btn.addEventListener('click', () => handleRetrieve(rental.id, btn));

        rentalsList.appendChild(card);
    });

    updateCountdowns();
    const countdownInterval = setInterval(updateCountdowns, 1000);
    rentalIntervals.push(countdownInterval);
}

function updateCountdowns() {
    const timers = document.querySelectorAll('.countdown-timer');
    const now = Date.now();

    timers.forEach(timer => {
        const endTime = parseInt(timer.dataset.end);
        const timeLeft = endTime - now;

        if (timeLeft <= 0) {
            timer.textContent = 'EXPIRED';
            timer.parentElement?.classList.add('expired');
        } else {
            const hours = Math.floor(timeLeft / (1000 * 60 * 60));
            const minutes = Math.floor((timeLeft % (1000 * 60 * 60)) / (1000 * 60));
            const seconds = Math.floor((timeLeft % (1000 * 60)) / 1000);

            if (hours >= 24) {
                const days = Math.floor(hours / 24);
                timer.textContent = `${days}d ${hours % 24}h left`;
            } else if (hours > 0) {
                timer.textContent = `${hours}h ${minutes}m left`;
            } else if (minutes > 0) {
                timer.textContent = `${minutes}m ${seconds}s left`;
            } else {
                timer.textContent = `${seconds}s left`;
            }

            if (timeLeft <= 5 * 60 * 1000) {
                timer.parentElement?.classList.add('warning');
            }
        }
    });
}

async function handleRetrieve(rentalId, button) {
    if (!rentalId) return;

    button.disabled = true;
    button.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Spawning...';

    try {
        await post('retrieveVehicle', { rentalId: rentalId });
        loadMyRentals();
    } catch (error) {
        button.disabled = false;
        button.innerHTML = '<i class="fa-solid fa-car"></i> Retrieve';
    }
}