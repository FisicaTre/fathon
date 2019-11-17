#    dfa.pyx - dfa algorithm of fathon package
#    Copyright (C) 2019  Stefano Bianchi
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

#cython: language_level=3

import numpy as np
cimport numpy as np
cimport cython
from cython.parallel import prange
import ctypes

cdef extern from "cLoops.h" nogil:
    double flucDFAForwCompute(double *y, int curr_win_size, int N, int pol_ord)
    double flucDFAForwBackwCompute(double *y, int curr_win_size, int N, int pol_ord)

cdef class DFA():
    """Detrended Fluctuation Analysis class.
    
    Parameters
    ----------
    n : numpy ndarray
        Array of window's sizes used for the computation.
    tsVec : iterable
        Time series used for the analysis.
    F : numpy ndarray
        Array containing the values of the fluctuations in every window.
    nStep : int
        Value of the step between two consecutive window's sizes in `n`.
    isComputed : bool
        Boolean value to know if `F` has been computed in order to prevent the computation of other functions that need `F`.
    """

    cdef:
        np.ndarray n
        np.ndarray tsVec, F
        int nStep
        bint isComputed

    def __init__(self, tsVec):
        self.tsVec = np.array(tsVec, dtype=float)
        self.tsVec = self.tsVec[~np.isnan(self.tsVec)]
        self.isComputed = False
		
    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cdef cy_flucCompute(self, np.ndarray[np.float64_t, ndim=1, mode='c'] vects, np.ndarray[int, ndim=1, mode='c'] vecn,
                        np.ndarray[np.float64_t, ndim=1, mode='c'] vecf, int polOrd, bint revSeg):
        cdef int nLen, tsLen
        cdef Py_ssize_t i
        
        nLen = len(vecn)
        tsLen = len(vects)
        if revSeg:
            for i in prange(nLen, nogil=True):
                vecf[i] = flucDFAForwBackwCompute(&vects[0], vecn[i], tsLen, polOrd)
        else:
            for i in prange(nLen, nogil=True):
                vecf[i] = flucDFAForwCompute(&vects[0], vecn[i], tsLen, polOrd)
		
    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef computeFlucVec(self, int nMin, int nMax=-999, int polOrd=1, int nStep=1, bint revSeg=False):
        """Computation of the fluctuations in every window.
        
        Parameters
        ----------
        nMin : int
            Size of the smaller window used to compute `F`.
        nMax : int, optional
            Size of the bigger window used to compute `F` (default : len(`tsVec`)/4)).
        polOrd : int, optional
            Order of the polynomial to be fitted in every window (default : 1).
        nStep : int, optional
            Step between two consecutive window's sizes (default : 1).
        revSeg : bool, optional
            If True, the computation of `F` is repeated starting from the end of the time series (default : False).

        Returns
        -------
        numpy ndarray
            Array `n` of window's sizes.
        numpy ndarray
            Array `F` containing the values of the fluctuations in every window.
        """
        cdef int tsLen = len(self.tsVec)
        
        if polOrd < 1:
            raise SystemExit('Error: Polynomial order must be greater than 0.')
        if nStep < 1:
            raise SystemExit('Error: Step for scales must be greater than 0.')
        if nMax == -999:
            nMax = int(tsLen/4)
        if nMax < 3 or nMin < 3:
            raise SystemExit('Error: Variable nMin and nMax must be at least equal to 3.')
        if nMax <= nMin:
            raise SystemExit('Error: Variable nMax must be greater than variable nMin.')
        if nMax > tsLen:
            raise SystemExit('Error: Variable nMax must be less than the input vector length.')
        if nMin < (polOrd+2):
            raise SystemExit('Error: Variable nMin must be at least equal to {}.'.format(polOrd+2))
        
        self.nStep = nStep
        self.n = np.arange(nMin, nMax+1, nStep, dtype=ctypes.c_int)
        self.F = np.zeros((len(self.n), ), dtype=ctypes.c_double)
        self.cy_flucCompute(np.array(self.tsVec, dtype=ctypes.c_double), self.n, self.F, polOrd, revSeg)
        self.isComputed = True
        return self.n, self.F

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    cpdef fitFlucVec(self, int n_start=-999, int n_end=-999):
        """Fit of the fluctuations values.
        
        Parameters
        ----------
        n_start : int, optional
            Size of the smaller window used to fit `F` (default : first value of `n`).
        n_end : int, optional
            Size of the bigger window used to fit `F` (default : last value of `n`).

        Returns
        -------
        float
            Slope of the fit.
        float
            Intercept of the fit.
        """
        cdef int start, end
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] log_fit
        
        if self.isComputed:
            if n_start == -999:
                n_start = self.n[0]
            if n_end == -999:
                n_end = self.n[-1]
            if n_start > n_end:
                raise SystemExit('Error: Variable n_end must be greater than variable n_start.')
            if (n_start < self.n[0]) or (n_end > self.n[-1]):
                raise SystemExit('Error: Fit limits must be included in interval [{}, {}].'.format(self.n[0], self.n[-1]))
            if (n_start not in self.n) or (n_end not in self.n):
                raise SystemExit('Error: Fit limits must be included in the n vector.')
            
            start = int((n_start - self.n[0]) / self.nStep)
            end = int((n_end - self.n[0]) / self.nStep)
            log_fit = np.polyfit(np.log(self.n[start:end+1]) , np.log(self.F[start:end+1]), 1)
            print('Fit limits: [{}, {}]'.format(n_start, n_end))
            print('Fit result: H_intercept = {:.2f}, H = {:.2f}'.format(log_fit[1], log_fit[0]))
            return log_fit[0], log_fit[1]
        else:
            raise SystemExit('Error: Fluctuations vector has not been computed yet.')

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef multiFitFlucVec(self, np.ndarray[np.int_t, ndim=2, mode='c'] limits_list):
        """Fit of the fluctuations values in different intervals at the same time.
        
        Parameters
        ----------
        limits_list : numpy ndarray
            kx2 array with the sizes of k starting and ending windows used to fit `F`.

        Returns
        -------
        numpy ndarray
            Slopes of the fits.
        numpy ndarray
            Intercepts of the fits.
        """
        cdef Py_ssize_t i
        cdef int limLen = len(limits_list)
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] list_H, list_H_intercept
        
        if self.isComputed:
            list_H = np.zeros((limLen, ), dtype=float)
            list_H_intercept = np.zeros((limLen, ), dtype=float)
            for i in range(limLen):
                print('----------')
                list_H[i], list_H_intercept[i] = self.fitFlucVec(n_start=limits_list[i][0], n_end=limits_list[i][1])
            print('----------')
            return list_H, list_H_intercept
        else:
            raise SystemExit('Error: Fluctuations vector has not been computed yet.')
